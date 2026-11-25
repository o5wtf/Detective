#!/usr/bin/env python3
"""Проверка файла дела по правилам диздока (разделы 2, 7, 8, 11, 13, 14, 15).

Запуск: python3 tools/validate_case.py cases/<дело>.json [--simulate [ТОН]] [--json]
Код возврата 0 — дело корректно, 1 — найдены ошибки.

--simulate ТОН — грубая симуляция темпа (раздел 11): игрок поговорил со всеми,
предъявил каждую открытую улику каждому агенту, поймал все доступные противоречия,
а давление от тона вопросов даёт каждому агенту не больше ТОН (по умолчанию 0).
Оговорки can_lie (раздел 8) не учитываются — это худший случай для игрока.
Печатает порядок событий и итоговый уровень каждого факта.
С --json вместо текста печатает итог симуляции в JSON (эталон для тестов RulesEngine).
"""
import json
import sys

EMOTIONS = {"calm", "neutral", "nervous", "scared", "sad", "angry", "controlled", "contemptuous"}
LIE_TYPES = {"must_lie", "can_lie", "cannot_lie"}
BREAKS = {"pressure", "evidence", "contradiction"}
FORMS = {"truth", "truth_full", "lie"}

# Баланс давления — раздел 11 диздока. Держать в синхроне с ним.
BALANCE = {
    "evidence_key": 10,       # предъявлена ключевая улика, связанная с агентом
    "evidence_normal": 5,     # предъявлена обычная улика, связанная с агентом
    "contradiction_lie": 10,  # поймана ложь агента (за каждую несломанную ложь в паре)
    "contradiction_plain": 5, # противоречие без лжи — обоим агентам
}


def breaks_list(f):
    b = f.get("breaks_lie_on")
    if b is None:
        return []
    return b if isinstance(b, list) else [b]


def validate(case):
    errors = []
    err = errors.append

    for key in ("id", "title", "briefing", "killer_id", "true_motive_id", "true_method_id",
                "motive_options", "method_options", "agents", "evidence"):
        if key not in case:
            err(f"нет обязательного поля дела: {key}")
    agents = case.get("agents", [])
    evidence = case.get("evidence", [])
    contradictions = case.get("contradictions", [])

    def unique_ids(items, what):
        ids = {}
        for it in items:
            i = it.get("id")
            if not i:
                err(f"{what} без id: {it}")
            elif i in ids:
                err(f"повторяющийся id {what}: {i}")
            ids[i] = it
        return ids

    agent_ids = unique_ids(agents, "агента")
    ev_ids = unique_ids(evidence, "улики")
    contr_ids = unique_ids(contradictions, "противоречия")
    facts = {}
    fact_owner = {}
    for a in agents:
        for f in a.get("facts", []):
            fid = f.get("id")
            if not fid:
                err(f"факт без id у агента {a.get('id')}")
                continue
            if fid in facts:
                err(f"повторяющийся id факта: {fid}")
            facts[fid] = f
            fact_owner[fid] = a.get("id")

    # Скрытая правда
    if case.get("killer_id") not in agent_ids:
        err(f"убийца {case.get('killer_id')} не найден среди агентов")
    motive_ids = {m.get("id") for m in case.get("motive_options", [])}
    method_ids = {m.get("id") for m in case.get("method_options", [])}
    if case.get("true_motive_id") not in motive_ids:
        err(f"true_motive_id {case.get('true_motive_id')} нет в motive_options")
    if case.get("true_method_id") not in method_ids:
        err(f"true_method_id {case.get('true_method_id')} нет в method_options")
    vc = case.get("victory_condition", "correct_accusation")
    if vc != "correct_accusation":
        err(f"victory_condition '{vc}' не поддерживается (только correct_accusation)")
    if case.get("starting_agent_id") and case["starting_agent_id"] not in agent_ids:
        err(f"starting_agent_id {case['starting_agent_id']} не найден")

    # Агенты
    for a in agents:
        aid = a.get("id")
        for key in ("name", "role", "personality", "prompt_background", "facts"):
            if key not in a or a[key] in ("", None):
                err(f"агент {aid}: нет поля {key}")
        emo = a.get("starting_emotion", "neutral")
        if emo not in EMOTIONS:
            err(f"агент {aid}: эмоция '{emo}' не из списка {sorted(EMOTIONS)}")
        for key in ("starting_pressure",):
            v = a.get(key, 0)
            if not isinstance(v, (int, float)) or not 0 <= v <= 100:
                err(f"агент {aid}: {key}={v} вне 0–100")
        for other in (a.get("relationships") or {}):
            if other not in agent_ids or other == aid:
                err(f"агент {aid}: relationships ссылается на неверного агента {other}")
        gender = a.get("gender") or ""
        if gender not in ("", "male", "female"):
            err(f"агент {aid}: gender '{gender}' не male/female")
        profanity = a.get("profanity") or ""
        if profanity not in ("", "never", "sometimes", "often"):
            err(f"агент {aid}: profanity '{profanity}' не never/sometimes/often")
        tts_voice = a.get("tts_voice") or ""
        if tts_voice and not (tts_voice[:1].isalpha() and tts_voice.isalnum() and 2 <= len(tts_voice) <= 32):
            err(f"агент {aid}: tts_voice '{tts_voice}' не имя голоса")

    # Факты
    lie_facts_in_contradictions = set()
    for c in contradictions:
        for side in ("a", "b"):
            if c.get(f"fact_{side}_form") == "lie":
                lie_facts_in_contradictions.add(c.get(f"fact_{side}_id"))
    for fid, f in facts.items():
        p = f"факт {fid}"
        for key in ("content_basic", "content_full"):
            if not f.get(key):
                err(f"{p}: пустое {key}")
        pb, pf = f.get("pressure_for_basic"), f.get("pressure_for_full")
        if pb is not None or pf is not None:
            if not isinstance(pb, (int, float)) or not isinstance(pf, (int, float)):
                err(f"{p}: пороги давления не числа")
            elif pf < pb:
                err(f"{p}: pressure_for_full ({pf}) < pressure_for_basic ({pb})")
        rel = f.get("related_evidence_ids", [])
        for e in rel:
            if e not in ev_ids:
                err(f"{p}: улика {e} не существует")
        if f.get("requires_evidence") and not rel:
            err(f"{p}: requires_evidence=true, но related_evidence_ids пуст")
        lt = f.get("lie_type")
        if lt not in LIE_TYPES:
            err(f"{p}: lie_type '{lt}' не из {sorted(LIE_TYPES)}")
        is_lie = f.get("is_lie")
        br = f.get("breaks_lie_on")
        if isinstance(br, list):
            if not br or len(set(br)) != len(br):
                err(f"{p}: breaks_lie_on — пустой список или повторы")
        bl = breaks_list(f)
        for b in bl:
            if b not in BREAKS:
                err(f"{p}: breaks_lie_on '{b}' недопустим")
        if lt in ("must_lie", "can_lie"):
            if is_lie is not True:
                err(f"{p}: lie_type={lt}, но is_lie не true")
            if not f.get("lie_text"):
                err(f"{p}: lie_type={lt}, но lie_text пуст")
        if lt == "cannot_lie":
            if is_lie:
                err(f"{p}: cannot_lie, но is_lie=true")
            if f.get("lie_text"):
                err(f"{p}: cannot_lie, но lie_text заполнен")
        if not is_lie and bl:
            err(f"{p}: у факта без лжи задан breaks_lie_on")
        has_sets = "breaks_with" in f
        if not has_sets and "evidence" in bl and not rel:
            err(f"{p}: breaks_lie_on=evidence, но нет related_evidence_ids")
        if not has_sets and "contradiction" in bl and fid not in lie_facts_in_contradictions:
            err(f"{p}: breaks_lie_on=contradiction, но нет противоречия с этим фактом в форме lie")
        if has_sets:
            validate_break_sets(fid, f, facts, ev_ids, fact_owner, err)

    # Противоречия
    for cid, c in contr_ids.items():
        pair = []
        for side in ("a", "b"):
            fid, form = c.get(f"fact_{side}_id"), c.get(f"fact_{side}_form")
            if fid not in facts:
                err(f"противоречие {cid}: факт {fid} не существует")
            elif form == "lie" and not facts[fid].get("is_lie"):
                err(f"противоречие {cid}: форма lie у факта {fid} без лжи")
            if form not in FORMS:
                err(f"противоречие {cid}: форма '{form}' не из {sorted(FORMS)}")
            pair.append((fid, form))
        if pair[0] == pair[1]:
            err(f"противоречие {cid}: оба утверждения одинаковы")
        if not c.get("description"):
            err(f"противоречие {cid}: нет description")

    # Условия открытия
    def check_cond(cond, where, ev_self):
        if cond is None:
            return
        if not isinstance(cond, dict):
            err(f"{where}: условие не объект: {cond}")
            return
        for op in ("AND", "OR"):
            if op in cond:
                if len(cond) != 1 or not isinstance(cond[op], list) or not cond[op]:
                    err(f"{where}: {op} должен быть единственным ключом с непустым списком")
                    return
                for sub in cond[op]:
                    check_cond(sub, where, ev_self)
                return
        t = cond.get("type")
        if t == "pressure_on_agent":
            return
        elif t == "dialogue_with":
            if cond.get("agent_id") not in agent_ids:
                err(f"{where}: агент {cond.get('agent_id')} не найден")
        elif t == "evidence_shown":
            if cond.get("evidence_id") not in ev_ids:
                err(f"{where}: улика {cond.get('evidence_id')} не найдена")
            if cond.get("evidence_id") == ev_self:
                err(f"{where}: улика требует предъявления самой себя")
            if "agent_id" in cond and cond["agent_id"] not in agent_ids:
                err(f"{where}: агент {cond['agent_id']} не найден")
        elif t == "evidence_mentioned":
            if cond.get("agent_id") not in agent_ids:
                err(f"{where}: агент {cond.get('agent_id')} не найден")
            if cond.get("evidence_id") not in ev_ids:
                err(f"{where}: улика {cond.get('evidence_id')} не найдена")
        elif t == "lie_broken":
            if cond.get("fact_id") not in facts:
                err(f"{where}: факт {cond.get('fact_id')} не найден")
        elif t == "inconsistency_created":
            if "contradiction_id" in cond and cond["contradiction_id"] not in contr_ids:
                err(f"{where}: противоречие {cond['contradiction_id']} не найдено")
        else:
            err(f"{where}: неизвестный тип условия '{t}'")

    # Улики
    for eid, e in ev_ids.items():
        for key in ("title", "short_description", "full_text", "type"):
            if not e.get(key):
                err(f"улика {eid}: нет поля {key}")
        for f in e.get("related_fact_ids", []):
            if f not in facts:
                err(f"улика {eid}: факт {f} не существует")
        for a in e.get("related_agent_ids", []):
            if a not in agent_ids:
                err(f"улика {eid}: агент {a} не существует")
        check_cond(e.get("unlock_condition"), f"улика {eid}", eid)

    # Взаимность связей факт <-> улика (предупреждения не блокируют)
    warnings = []
    for eid, e in ev_ids.items():
        for f in e.get("related_fact_ids", []):
            if f in facts and eid not in facts[f].get("related_evidence_ids", []):
                warnings.append(f"улика {eid} ссылается на факт {f}, но факт не ссылается на улику")
    return errors, warnings


def effective_sets(fact, contradictions):
    if "breaks_with" in fact and isinstance(fact.get("breaks_with"), list):
        return fact["breaks_with"]
    sets = []
    modes = set(breaks_list(fact))
    if "evidence" in modes:
        for evidence_id in fact.get("related_evidence_ids", []):
            sets.append([{"type": "evidence_shown", "evidence_id": evidence_id}])
    if "contradiction" in modes:
        for contradiction in contradictions:
            partner = None
            if contradiction.get("fact_a_id") == fact.get("id") and contradiction.get("fact_a_form") == "lie":
                partner = (contradiction.get("fact_b_id"), contradiction.get("fact_b_form"))
            elif contradiction.get("fact_b_id") == fact.get("id") and contradiction.get("fact_b_form") == "lie":
                partner = (contradiction.get("fact_a_id"), contradiction.get("fact_a_form"))
            if not partner or partner[1] not in ("truth", "truth_full"):
                continue
            item = {"type": "testimony_retold", "fact_id": partner[0]}
            if partner[1] == "truth_full":
                item["form"] = "truth_full"
            sets.append([item])
    return sets


def witness_counts(target, witness_id, facts, owner, broken):
    if not target.get("related_evidence_ids"):
        return True
    witness_owner = owner.get(witness_id)
    for fid, fact in facts.items():
        if owner.get(fid) != witness_owner or fid == witness_id or not fact.get("is_lie"):
            continue
        if fid in broken or not fact.get("related_evidence_ids"):
            continue
        if set(fact.get("related_evidence_ids", [])) & set(target.get("related_evidence_ids", [])):
            return False
    return True


def set_holds(case, fact, liar, shown, retold, broken, owner, facts):
    sets = [items for items in effective_sets(fact, case.get("contradictions", [])) if items]
    if not sets:
        return False

    def item_ok(item):
        kind = item.get("type")
        if kind == "evidence_shown":
            return (item.get("evidence_id"), liar) in shown
        if kind != "testimony_retold":
            return False
        told = item.get("fact_id")
        if not witness_counts(fact, told, facts, owner, broken):
            return False
        forms = {form for listener, fid, form in retold if listener == liar and fid == told}
        if item.get("form") == "truth_full":
            return "full" in forms
        return "basic" in forms or "full" in forms

    return any(all(item_ok(item) for item in items) for items in sets)


def validate_break_sets(fid, fact, facts, ev_ids, fact_owner, err):
    p = f"факт {fid}"
    value = fact.get("breaks_with")
    if not isinstance(value, list):
        err(f"{p}: breaks_with не список наборов")
        return
    if not fact.get("is_lie") and value:
        err(f"{p}: у факта без лжи задан breaks_with")
    seen_sets = set()
    for raw_set in value:
        if not isinstance(raw_set, list) or not raw_set:
            err(f"{p}: пустой набор")
            continue
        seen_items = set()
        for item in raw_set:
            if not isinstance(item, dict) or "AND" in item or "OR" in item:
                err(f"{p}: в наборе недопустима группа И/ИЛИ")
                continue
            if "agent_id" in item:
                err(f"{p}: в пункте набора не пишется agent_id")
            kind = str(item.get("type", ""))
            if kind == "evidence_shown":
                evidence_id = item.get("evidence_id")
                if evidence_id not in ev_ids:
                    err(f"{p}: улика {evidence_id} не найдена")
                mark = f"e:{evidence_id}"
                if mark in seen_items:
                    err(f"{p}: повтор пункта {evidence_id}")
                seen_items.add(mark)
            elif kind == "testimony_retold":
                told = item.get("fact_id")
                if told not in facts:
                    err(f"{p}: показание {told} не найдено")
                elif fact_owner.get(told) == fact_owner.get(fid):
                    err(f"{p}: breaks_with пересказывает своё показание {told}")
                form = str(item.get("form", ""))
                if form not in ("", "truth_full"):
                    err(f"{p}: форма пересказа '{form}' недопустима")
                mark = f"t:{told}:{form}"
                if mark in seen_items:
                    err(f"{p}: повтор пересказа {told}")
                seen_items.add(mark)
            else:
                err(f"{p}: неизвестный вид пункта '{kind}'")
        fingerprint = json.dumps(raw_set, ensure_ascii=False, sort_keys=True)
        if fingerprint in seen_sets:
            err(f"{p}: повтор набора")
        seen_sets.add(fingerprint)


def publish_errors(case):
    facts, owner = {}, {}
    for agent in case.get("agents", []):
        for fact in agent.get("facts", []):
            facts[fact.get("id")] = fact
            owner[fact.get("id")] = agent.get("id")
    breakable = set()
    for _ in range(len(facts) + 2):
        grew = False
        for fid, fact in facts.items():
            if fid in breakable or fact.get("lie_type") not in ("must_lie", "can_lie"):
                continue
            if any(prior not in breakable for prior in (fact.get("requires_broken_lies") or [])):
                continue
            for raw_set in effective_sets(fact, case.get("contradictions", [])):
                if set_collectable(raw_set, facts, breakable):
                    breakable.add(fid)
                    grew = True
                    break
        if not grew:
            break
    errors = []
    for fid, fact in facts.items():
        if fact.get("lie_type") != "must_lie" or fact.get("is_lie") is not True:
            continue
        sets = effective_sets(fact, case.get("contradictions", []))
        if not sets:
            errors.append(f"факт {fid}: «Всегда врёт» без наборов «Чем можно сломать»")
        elif fid not in breakable:
            errors.append(f"факт {fid}: ни один набор не собрать")
    return errors


def set_collectable(raw_set, facts, breakable):
    if not isinstance(raw_set, list) or not raw_set:
        return False
    for item in raw_set:
        if not isinstance(item, dict):
            return False
        kind = item.get("type")
        if kind == "evidence_shown":
            continue
        if kind != "testimony_retold" or item.get("fact_id") not in facts:
            return False
        told = facts[item["fact_id"]]
        if not told.get("is_lie") or told.get("lie_type") == "cannot_lie":
            continue
        if told.get("lie_type") == "can_lie" and item.get("form") != "truth_full":
            continue
        if item.get("fact_id") not in breakable:
            return False
    return True


def eval_cond(cond, st):
    if cond is None:
        return True
    if "AND" in cond:
        return all(eval_cond(c, st) for c in cond["AND"])
    if "OR" in cond:
        return any(eval_cond(c, st) for c in cond["OR"])
    t = cond["type"]
    if t == "dialogue_with":
        return True  # игрок говорит со всеми
    if t == "evidence_shown":
        return cond["evidence_id"] in st["shown_any"]
    if t == "evidence_mentioned":
        return True
    if t == "lie_broken":
        return cond.get("fact_id") in st.get("broken", set())
    if t == "inconsistency_created":
        cid = cond.get("contradiction_id") or ""
        return bool(cid) and cid in st.get("contr", set())
    if t == "testimony_retold":
        return False
    return False


def simulate(case, tone):
    agents = {a["id"]: a for a in case["agents"]}
    facts, owner = {}, {}
    for a in case["agents"]:
        for f in a["facts"]:
            facts[f["id"]] = f
            owner[f["id"]] = a["id"]
    ev = {e["id"]: e for e in case["evidence"]}
    ev_agents = {}
    for eid, e in ev.items():
        ev_agents[eid] = set(e.get("related_agent_ids", []))
    unlocked, broken, level = set(), set(), {}
    st = {"p": {aid: min(100, a.get("starting_pressure", 0) + tone) for aid, a in agents.items()},
          "shown_any": set(), "contr": set(), "broken": broken}
    shown = set()   # (evidence, agent)
    retold = set()  # (listener, fact, form)
    log = []

    def bump(aid, n, why):
        st["p"][aid] = min(100, st["p"][aid] + n)
        log.append(f"  {aid}: +{n} ({why}) -> {st['p'][aid]}")

    def ev_ok(fid):
        f = facts[fid]
        if not f.get("requires_evidence"):
            return True
        return any((e, owner[fid]) in shown for e in f.get("related_evidence_ids", []))

    def heard(fid, form):
        lv = level.get(fid)
        if form == "lie":
            return facts[fid].get("is_lie")  # ложь звучит с самого начала
        if form == "truth_full":
            return lv == "full"
        return lv in ("basic", "full")

    changed = True
    while changed:
        changed = False
        for eid, e in ev.items():
            if eid not in unlocked and eval_cond(e.get("unlock_condition"), st):
                unlocked.add(eid)
                log.append(f"улика открыта: {eid}")
                changed = True
        for eid in [e for e in ev if e in unlocked]:  # порядок файла дела
            for aid in agents:
                if (eid, aid) not in shown:
                    shown.add((eid, aid))
                    st["shown_any"].add(eid)
                    if aid in ev_agents[eid]:
                        bump(aid, BALANCE["evidence_key" if ev[eid].get("is_key") else "evidence_normal"],
                             f"предъявлена {eid}")
                    changed = True
        for fid, f in facts.items():
            aid = owner[fid]
            if f.get("is_lie") and f.get("lie_type") == "can_lie" and fid not in broken:
                for listener in agents:
                    if listener != aid:
                        retold.add((listener, fid, "basic"))
            lv = level.get(fid)
            forms = []
            if lv in ("basic", "full"):
                forms.append("basic")
            if lv == "full":
                forms.append("full")
            for listener in agents:
                if listener == aid:
                    continue
                for form in forms:
                    retold.add((listener, fid, form))
        for fid, f in facts.items():
            aid = owner[fid]
            p = st["p"][aid]
            if f.get("is_lie") and fid not in broken:
                prior = f.get("requires_broken_lies") or []
                ready = all(item in broken for item in prior)
                hit = ready and set_holds(case, f, aid, shown, retold, broken, owner, facts)
                if hit:
                    broken.add(fid)
                    log.append(f"ложь сломана: {fid}")
                    changed = True
                    continue
                continue
            new = None
            prior = f.get("requires_broken_lies") or []
            if any(item not in broken for item in prior):
                new = None
            elif ev_ok(fid):
                new = "full"
            elif fid in broken:
                new = "basic"
            if new and level.get(fid) != new and not (level.get(fid) == "full"):
                level[fid] = new
                log.append(f"факт {new}: {fid} (давление {aid} = {p})")
                changed = True
        for c in case.get("contradictions", []):
            if c["id"] in st["contr"]:
                continue
            if heard(c["fact_a_id"], c["fact_a_form"]) and heard(c["fact_b_id"], c["fact_b_form"]):
                st["contr"].add(c["id"])
                log.append(f"противоречие: {c['id']}")
                liars = [c[f"fact_{s}_id"] for s in "ab" if c[f"fact_{s}_form"] == "lie"]
                if liars:
                    for lf in liars:
                        if lf not in broken:
                            bump(owner[lf], BALANCE["contradiction_lie"], f"противоречие {c['id']}")
                else:
                    for s in "ab":
                        bump(owner[c[f"fact_{s}_id"]], BALANCE["contradiction_plain"], f"противоречие {c['id']}")
                changed = True
    return log, level, broken, st, unlocked


def main():
    args = sys.argv[1:]
    if not args or args[0].startswith("-"):
        print(__doc__)
        return 2
    with open(args[0], encoding="utf-8") as fh:
        case = json.load(fh)
    errors, warnings = validate(case)
    for w in warnings:
        print("ПРЕДУПРЕЖДЕНИЕ:", w)
    for e in errors:
        print("ОШИБКА:", e)
    if errors:
        print(f"Дело не прошло проверку: ошибок {len(errors)}.")
        return 1
    print(f"Дело корректно. Агентов: {len(case['agents'])}, фактов: "
          f"{sum(len(a['facts']) for a in case['agents'])}, улик: {len(case['evidence'])}, "
          f"противоречий: {len(case.get('contradictions', []))}.", file=sys.stderr if "--json" in args else sys.stdout)
    if "--simulate" in args:
        i = args.index("--simulate")
        tone = int(args[i + 1]) if len(args) > i + 1 else 0
        log, level, broken, st, unlocked = simulate(case, tone)
        if "--json" in args:
            out = {"tone": tone,
                   "fact_levels": {f["id"]: ("lie" if f.get("is_lie") and f["id"] not in broken
                                             else level.get(f["id"], "closed"))
                                   for a in case["agents"] for f in a["facts"]},
                   "pressure": st["p"],
                   "unlocked_evidence": sorted(unlocked),
                   "contradictions": sorted(st["contr"]),
                   "broken_lies": sorted(broken)}
            print(json.dumps(out, ensure_ascii=False, indent=2, sort_keys=True))
            return 0
        print(f"\nСимуляция, тон до +{tone} на агента:")
        for line in log:
            print(line)
        print("\nИтог по фактам:")
        for a in case["agents"]:
            for f in a["facts"]:
                lv = level.get(f["id"], "закрыт")
                if f.get("is_lie") and f["id"] not in broken:
                    lv = "ложь держится"
                print(f"  {f['id']}: {lv}")
        print("Давление:", st["p"])
        print("Не открыты улики:", sorted({e["id"] for e in case["evidence"]} - unlocked) or "нет")
        print("Не пойманы противоречия:",
              sorted({c["id"] for c in case.get("contradictions", [])} - st["contr"]) or "нет")
    return 0


if __name__ == "__main__":
    sys.exit(main())
