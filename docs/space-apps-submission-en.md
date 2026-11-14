# Zuma — Space Apps project description (draft)

**Challenge:** Create Health Monitoring Software for Astronauts on Space Missions

Zuma is a local desktop prototype that helps a crew member record self-reported
sleep, fatigue, stress and mood, and complete short cognitive games. The user
chooses a profile, saves a questionnaire and plays a sliding puzzle, matching
pairs, arithmetic or a number-sequence task. Each game records its own event log
and a snapshot of the saved questionnaire. A local service validates the log,
stores it, and makes a descriptive report and comparison with a compatible
earlier game when one exists. Questionnaire values attached to games can also be
viewed in the Trends screen. If delivery fails, the game result stays in a local
outbox for retry with the same identifier. The prototype works without an
internet connection after its dependencies are installed; the local language
model is optional.

## Space-agency resources and how they informed the project

- [NASA: Risks of Human Spaceflight](https://www.nasa.gov/hrp/risks/) provides
  the mission-health context for the project.
- [NASA: Sleep Loss, Circadian Desynchronization and Work Overload](https://www.nasa.gov/directorates/esdmd/hhp/risk-of-performance-decrements-and-adverse-health-outcomes-resulting-from-sleep-loss-circadian-desynchronization-and-work-overload/)
  describes why sleep and performance are relevant during spaceflight; this
  motivated the self-reported sleep field and repeated observations.
- [NASA: Behavioral Health Risk](https://www.nasa.gov/directorates/esdmd/hhp/behavioral-health-risk/)
  provides context for mood, fatigue, stress and cognitive functioning.

These publications inform the choice and explanation of indicators. The app
does **not** contain astronaut measurements from NASA or calculate clinically
validated risk scores from these sources. The four games and questionnaire
scales have not been medically validated. The tool does not diagnose, prescribe
treatment, measure physical vital signs or replace a flight surgeon. Reports
show missing comparisons as unavailable, not zero. The timestamp of a game is
not the time its questionnaire was filled in; reusing a saved questionnaire can
produce repeated values. Demo data are synthetic and clearly marked.

## Technology and AI disclosure

Godot 4/GDScript provides the desktop interface and games; a local Go/SQLite
service validates and stores events and produces reports. When explicitly
requested and available, Qwen3 through a local Ollama instance selects from
server-generated facts; numeric calculations do not depend on the model.
OpenAI Codex was used to assist with implementation, testing and documentation.
The team should add any other AI tools or generated materials it actually used
and verify the wording against the current submission form.

## Before submitting

This is a draft, not a submitted entry. The team must supply and verify its own
team details, final project URL, public access, source and asset permissions,
AI disclosure and demonstration. The current application interface is in
Russian; prepare an English project page and, if the demo is in Russian,
English captions where required by the current rules. Check the current
[submission guide](https://www.spaceappschallenge.org/resources/project-submission-guide/)
and the chosen local event's rules and deadlines before submitting. The
[2026 event page](https://www.spaceappschallenge.org/2026/) states that project
submission closes on 15 November at 11:59 p.m. local time.

The [2025 judging guidance](https://spaceapps-v2-staging.s3.amazonaws.com/media/documents/Final_Space_Apps_2025_Judging_Guidelines_for_web.pdf) mentioned a maximum seven-slide deck or 30-second
video and unrestricted project links; those are useful preparation targets,
but the team must confirm the applicable 2026 rules rather than assume last
year's criteria remain unchanged. MIT was selected for the project's own code;
the user confirmed that all project rights holders agree. Third-party components
retain their own licenses, and their notices should accompany distributions.
