# Research & Scientific Background

This document outlines the scientific foundation and NASA research standards behind our astronaut health and cognitive monitoring application.

---

## 1. Cognitive Performance & Vigilance Monitoring (PVT Methodology)

* **The Problem:** During long-duration space missions, astronauts face microgravity, heavy operational workloads, and disrupted sleep schedules. These factors significantly impact reaction time, sustained attention, and cognitive agility.
* **NASA Standard:** NASA's Human Research Program (HRP) actively tracks cognitive and behavioral health risks. One of the primary tools used in spaceflight is the **Psychomotor Vigilance Test (PVT)**—a rapid, reaction-time task proven sensitive to fatigue and sleep loss.
* **Our Approach:** Our application integrates interactive reaction and memory mini-games built in Godot. Instead of relying solely on clinical questionnaires, crew members engage in quick, gamified cognitive checks that mirror PVT principles to track alertness over time.
* **Official Sources & References:**
  * [NASA Human Research Program (HRP): Risk of Adverse Cognitive or Behavioral Conditions](https://www.nasa.gov/hrp/)
  * Dinges, D. F., & Powell, J. W. (1985). *Microcomputer analyses of performance on a portable, simple visual RT task during sustained operations*. Behavior Research Methods, Instruments, & Computers.

---

## 2. Sleep Deprivation & Circadian Rhythm Disruption

* **The Problem:** On the International Space Station (ISS), astronauts experience 16 sunrises and sunsets every 24 hours, disrupting natural circadian rhythms and frequently leading to sleep restriction and cumulative fatigue.
* **NASA Standard:** Continuous monitoring of physiological metrics (such as resting heart rate and sleep duration) helps predict fatigue-related risks before they compromise mission safety.
* **Our Approach:** Through smart watch integration, our system passively collects heart rate telemetry, allowing the backend (Go server) to correlate physiological strain and rest patterns with cognitive test scores.
* **Official Sources & References:**
  * [NASA Task Book (Space Life Sciences): Circadian and Sleep Research on the ISS](https://taskbook.nasaprs.com/)
  * Czeisler, C. A., et al. (2015). *Sleep and circadian rhythms in space flight*.

---

## 3. Stress & Heart Rate Variability (HRV)

* **The Problem:** High-stakes space operations, isolation, and confinement elevate psychological and physiological stress levels, which require objective, non-invasive monitoring.
* **NASA Standard:** Heart Rate Variability (HRV) and resting heart rate trends serve as reliable, non-invasive biomarkers of autonomic nervous system balance and acute stress.
* **Our Approach:** Biometric data streamed from wearable devices is logged and analyzed locally to detect anomalies and provide timely wellness feedback without requiring constant Earth-to-space connectivity.
* **Official Sources & References:**
  * [NASA HRP: Behavioral Health and Performance](https://www.nasa.gov/hrp/elements/bhp/)
  * Task Force of the European Society of Cardiology. (1996). *Heart rate variability: standards of measurement, physiological interpretation and clinical use*.

---

## 4. Autonomous & Offline-First Architecture

* **The Problem:** Deep-space missions (such as lunar or Mars transit) experience significant communication latency and blackout periods, making cloud-dependent health platforms unreliable.
* **Our Approach:** Combining a local Godot client, a lightweight Go backend, and an on-device local AI model ensures full offline functionality, data persistence, and real-time reporting regardless of network availability.

* ---

## 5. Summary: NASA Science to System Architecture

| Spaceflight Risk Factor | NASA Standard / Biomarker | Our Application Feature |
| :--- | :--- | :--- |
| **Cognitive Fatigue & Attention Loss** | Psychomotor Vigilance Test (PVT) | Interactive Godot reaction & memory mini-games |
| **Circadian Rhythm Disruption** | Sleep & activity tracking | Smart watch passive telemetry integration |
| **Psychological & Physical Stress** | Heart Rate Variability (HRV) | Real-time biometric logging & Go backend analytics |
| **Deep-Space Communication Latency** | Autonomous crew support systems | Offline-first architecture & local on-device AI model |
