package com.o5wtf.detective;

import android.content.res.AssetManager;

import com.k2fsa.sherpa.onnx.FeatureConfig;
import com.k2fsa.sherpa.onnx.OfflineModelConfig;
import com.k2fsa.sherpa.onnx.OfflineRecognizer;
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig;
import com.k2fsa.sherpa.onnx.OfflineStream;
import com.k2fsa.sherpa.onnx.OfflineTransducerModelConfig;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONObject;

import java.io.File;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Offline Parakeet on a background thread. Audio and keys are not logged.
 * A null AssetManager tells sherpa to read the model from absolute paths.
 */
public class SherpaPlugin extends GodotPlugin {
    private static final int SAMPLE_RATE = 16000;
    private static final String[] MODEL_FILES = {
            "encoder.int8.onnx",
            "decoder.int8.onnx",
            "joiner.int8.onnx",
            "tokens.txt",
    };

    private final ExecutorService loader = Executors.newSingleThreadExecutor(runnable -> {
        Thread thread = new Thread(runnable, "sherpa-load");
        thread.setDaemon(true);
        return thread;
    });
    private final Object lock = new Object();
    private int generation = 0;
    private String state = "";
    private OfflineRecognizer recognizer;

    public SherpaPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "SherpaOnnx";
    }

    @UsedByGodot
    public String start_load(String dir) {
        File folder = new File(dir == null ? "" : dir);
        for (String name : MODEL_FILES) {
            if (!new File(folder, name).isFile()) {
                synchronized (lock) {
                    state = "load_failed";
                }
                return "load_failed";
            }
        }
        final int ticket;
        synchronized (lock) {
            generation += 1;
            ticket = generation;
            releaseLocked();
            state = "loading";
        }
        loader.execute(() -> load(folder, ticket));
        return "loading";
    }

    @UsedByGodot
    public String load_state() {
        synchronized (lock) {
            return state;
        }
    }

    @UsedByGodot
    public void unload() {
        synchronized (lock) {
            generation += 1;
            releaseLocked();
            state = "";
        }
    }

    @UsedByGodot
    public String transcribe_wav(byte[] wav) {
        OfflineRecognizer current;
        synchronized (lock) {
            current = recognizer;
        }
        if (current == null) {
            return crashJson();
        }
        float[] samples = pcm16Mono16k(wav);
        if (samples == null) {
            return crashJson();
        }
        OfflineStream stream = null;
        try {
            synchronized (lock) {
                if (recognizer != current) {
                    return crashJson();
                }
                stream = current.createStream();
                stream.acceptWaveform(samples, SAMPLE_RATE);
                current.decode(stream);
                String text = current.getResult(stream).getText();
                return okJson(text == null ? "" : text);
            }
        } catch (Throwable ignored) {
            return crashJson();
        } finally {
            if (stream != null) {
                try {
                    stream.release();
                } catch (Throwable ignored) {
                    // The phrase is already decoded or already failed.
                }
            }
        }
    }

    private void load(File folder, int ticket) {
        OfflineRecognizer created = null;
        try {
            OfflineTransducerModelConfig transducer = new OfflineTransducerModelConfig();
            transducer.setEncoder(new File(folder, "encoder.int8.onnx").getAbsolutePath());
            transducer.setDecoder(new File(folder, "decoder.int8.onnx").getAbsolutePath());
            transducer.setJoiner(new File(folder, "joiner.int8.onnx").getAbsolutePath());

            OfflineModelConfig model = new OfflineModelConfig();
            model.setTransducer(transducer);
            model.setTokens(new File(folder, "tokens.txt").getAbsolutePath());
            model.setNumThreads(2);
            model.setDebug(false);
            model.setProvider("cpu");
            model.setModelType("nemo_transducer");

            FeatureConfig features = new FeatureConfig();
            features.setSampleRate(SAMPLE_RATE);
            features.setFeatureDim(80);

            OfflineRecognizerConfig config = new OfflineRecognizerConfig();
            config.setFeatConfig(features);
            config.setModelConfig(model);
            config.setDecodingMethod("greedy_search");

            created = new OfflineRecognizer((AssetManager) null, config);
            synchronized (lock) {
                if (ticket != generation) {
                    created.release();
                    return;
                }
                recognizer = created;
                created = null;
                state = "";
            }
        } catch (Throwable ignored) {
            synchronized (lock) {
                if (ticket == generation) {
                    state = "load_failed";
                }
            }
        } finally {
            if (created != null) {
                try {
                    created.release();
                } catch (Throwable ignored) {
                    // A superseded load has nothing left to keep.
                }
            }
        }
    }

    private void releaseLocked() {
        if (recognizer != null) {
            try {
                recognizer.release();
            } catch (Throwable ignored) {
                // Dropping the model must not throw into GDScript.
            }
            recognizer = null;
        }
    }

    private static float[] pcm16Mono16k(byte[] wav) {
        if (wav == null || wav.length < 44) {
            return null;
        }
        if (!ascii(wav, 0, "RIFF") || !ascii(wav, 8, "WAVE")) {
            return null;
        }
        int channels = 0;
        int rate = 0;
        int bits = 0;
        int data = -1;
        int dataSize = 0;
        int cursor = 12;
        while (cursor + 8 <= wav.length) {
            String chunk = new String(wav, cursor, 4, StandardCharsets.US_ASCII);
            int size = int32(wav, cursor + 4);
            int body = cursor + 8;
            if (size < 0 || body + size > wav.length) {
                return null;
            }
            if ("fmt ".equals(chunk) && size >= 16) {
                int format = int16(wav, body);
                channels = int16(wav, body + 2);
                rate = int32(wav, body + 4);
                bits = int16(wav, body + 14);
                if (format != 1) {
                    return null;
                }
            } else if ("data".equals(chunk)) {
                data = body;
                dataSize = size;
                break;
            }
            cursor = body + size + (size & 1);
        }
        if (data < 0 || channels != 1 || rate != SAMPLE_RATE || bits != 16) {
            return null;
        }
        int samples = dataSize / 2;
        float[] pcm = new float[samples];
        ByteBuffer buffer = ByteBuffer.wrap(wav, data, samples * 2).order(ByteOrder.LITTLE_ENDIAN);
        for (int index = 0; index < samples; index++) {
            pcm[index] = buffer.getShort() / 32768.0f;
        }
        return pcm;
    }

    private static boolean ascii(byte[] wav, int offset, String text) {
        byte[] expected = text.getBytes(StandardCharsets.US_ASCII);
        if (offset + expected.length > wav.length) {
            return false;
        }
        for (int index = 0; index < expected.length; index++) {
            if (wav[offset + index] != expected[index]) {
                return false;
            }
        }
        return true;
    }

    private static int int16(byte[] wav, int offset) {
        return (wav[offset] & 0xff) | (wav[offset + 1] << 8);
    }

    private static int int32(byte[] wav, int offset) {
        return (wav[offset] & 0xff)
                | ((wav[offset + 1] & 0xff) << 8)
                | ((wav[offset + 2] & 0xff) << 16)
                | ((wav[offset + 3] & 0xff) << 24);
    }

    private static String okJson(String text) {
        JSONObject obj = new JSONObject();
        try {
            obj.put("ok", true);
            obj.put("text", text);
            obj.put("crash", false);
        } catch (Throwable ignored) {
            return crashJson();
        }
        return obj.toString();
    }

    private static String crashJson() {
        return "{\"ok\":false,\"text\":\"\",\"crash\":true}";
    }
}
