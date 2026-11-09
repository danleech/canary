# Major cyber incidents — WATCH (stable)
id cyber · Technology & Cyber · horizon acute · checked 2026-11-09T05:53Z · at this level since 2026-10-31T11:26Z · stale after 2026-11-09T19:53Z
Assessed by an AI model (Anthropic Claude) against published rubrics; not a forecast or advice · CC BY 4.0 · https://canary.danleech.com/s/cyber

Value: Cold-chain attacks; OpenSSH flaw exploited
Rated on: Attacks disrupting critical services and large retailers (European cold-chain attacks; US advisory 5 Nov): Watch. No national-scale attack found.
Basis: judged — The AI assessor's reading of 3 sources from 3 outlets against the rubric. Check the sources before relying on it.

Refrigeration-control attacks hit shops across Europe and French blood banks; US agencies issued a warning on 5 Nov

Why it's at this level: Attacks on refrigeration controls hit stores in Belgium, Luxembourg and Sweden in a second wave, with later reports from Finland, Ireland, Estonia and the Netherlands (Help Net Security). France's blood service confirmed on 3 Nov that cold rooms were affected through a supplier, with no products lost (The Register). Five US agencies warned on 5 Nov of attacks on these systems, naming no culprit. GreyNoise first saw an OpenSSH authentication bypass exploited on 7 Nov, on a limited scale. No national-scale attack on power, health or finance had been found as of 9 Nov.

What this means for you: Food retailers, cold-storage operators and health services using connected refrigeration are most exposed. Organisations can follow NCSC guidance and the joint CISA and FBI advisory; administrators can check vendor advisories for OpenSSH.

Why it matters: Ransomware and state hacking now shut down hospitals, retailers, carmakers and airports for weeks.
What moves it: Ransomware gangs, state actors, zero-days, supply-chain compromises.

Rubric — Alert: National-scale attack on critical infrastructure (power, health, finance), or a destructive state-attributed attack. | Watch: Ransomware or attack disrupting a large company or critical service, or a mass-exploited zero-day. | Normal: No major incidents disrupting critical services this week.

Sources:
- US agencies warn attackers are targeting refrigeration systems that protect food and medicine (2026-11-06) https://www.helpnetsecurity.com/2026/11/06/cyberattacks-refrigeration-systems-cisa-fbi/
- Cyberattack on French plasma stores is enough to make your blood boil (2026-11-04) https://www.theregister.com/security/2026/11/04/cyberattack-on-french-plasma-stores-is-enough-to-make-your-blood-boil/5307519
- SSHole (CVE-2026-123158) Activity 2026 (2026-11-08) https://sshole.events.greynoise.io/
