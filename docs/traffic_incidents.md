# Traffic incidents (v0.03A1)

Owner playtest: hitting another vehicle felt dead. In Colombo a bump gets a
horn, a shout, and sometimes a driver who gets out to tell you about it.
Non-graphic and non-violent by design: no fighting, no contact, no chase,
no injury, no police/fines (later sprints decide consequences).

## Flow

`TukController` → `EventBus.collision_event` → `TrafficIncidentManager`
(no logic in the tuk). Only `TRAFFIC` collisions with a valid
`other_agent_id` qualify; walls, kerbs and rollovers never do.

| Tier | Rule (`IncidentRules.tier_for`) | Typical response |
|---|---|---|
| LIGHT | MINOR and impact < 14 km/h | angry horn and/or shout from the moving vehicle (~1 s); a hothead may stop and yell |
| MODERATE | MINOR and impact ≥ 14 km/h | vehicle stops, horn burst; driver gets out 15–85 % (temperament) |
| MAJOR | CollisionEvent MAJOR | vehicle stops, repeated horn; driver gets out ≥ 85 % (any temperament) |

Altercation phases: `STOPPING → (HONKING | EXITING → APPROACHING → ARGUING →
RETURNING) → RESUMING`. The driver walks to 2.4 m from the tuk, gestures
(ANGRY indicator, agitated bob) and shouts temperament lines; after the
argument they walk back and the vehicle resumes. If the player drives away
(well beyond where the incident started, or off briskly) the driver shouts
once and walks back — no pursuit (approach limited to 6 s). Hard cap 22 s. Typical MAJOR ≈ 8–10 s,
MODERATE 3–7 s.

## Driver temperaments (`resources/traffic/temperament_*.tres`)

| | weight | horn | hothead escalation on a scrape | exit (moderate) | exit (major) | argue |
|---|---|---|---|---|---|---|
| CALM | 0.45 | 50 % | 0 % | 15 % | 85 % | 1.8–2.8 s |
| IMPATIENT | 0.35 | 90 % | 15 % | 45 % | 95 % | 2.4–3.8 s |
| HOTHEAD | 0.20 | 100 % | 50 % | 85 % | 100 % | 3.4–5.2 s |

Severity dominates (MAJOR floor `major_min_exit_chance` 0.85; MAJOR argues
×1.3, MODERATE ×0.8).

## Drivers are HumanAgents

Role `TRAFFIC_DRIVER`, `DriverBehaviour`, states `EXITING_VEHICLE →
APPROACHING_PLAYER → ARGUING → RETURNING_TO_VEHICLE` (whitelisted
transitions). While driving they are logically IN_VEHICLE with no agent; an
agent is taken from the shared pool only for the altercation (one slot is
always reserved) and released after. Drivers are people: pedestrian safety
applies to them like anyone else (hitting one is a pedestrian impact).

## Limits

- One altercation at a time; further traffic collisions during it only horn
  (counted as suppressed). Per-vehicle cooldown 8 s, light reactions ≥ 0.8 s apart.
- The held vehicle (`TrafficAgent.incident_hold`) is never despawned or
  recycled; followers stop through normal IDM following and occasionally horn
  (≤ 1 per 1.5 s). After resolution everything resumes; no pile-up logic.
- Never touches score, combo or fare. Existing collision penalties unchanged.

## Passenger reactions

Data on `PassengerProfile`: `collision_reaction_key`, `incident_reaction_key`.

| Passenger | Collision | Incident |
|---|---|---|
| Late Executive | "We don't have time for this!" | "Don't argue, just go — I'm late!" |
| Careful Aunty | "Aiyo! I told you to be careful!" | "Say sorry, putha, and let's go." |
| Thrill Seeker | "Hey — not like that, that's a crash!" (still negative) | "Ha! Now we have a show." |

Satisfaction formula unchanged — the collision was already counted and the
lost time counts naturally.

## Audio / localisation hooks

`EventBus.traffic_horn(pos, pattern ANGRY|REPEATED|NEARBY)`,
`driver_shout(pos, key)`, `traffic_incident_started(tier, pos)`,
`traffic_incident_resolved(tier)`. `IncidentBubbles` shows placeholder text
(Sri Lankan English lines, "PAAAN!" horns). Colloquial Sinhala/Tamil lines,
horn patterns, gestures and VO belong to the production audio sprint; si/ta
keys exist and fall back to English. No offensive language, no stereotypes.
