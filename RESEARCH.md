# Research & Scientific Background

This document records the research motivation behind Zuma. The background references are not evidence of clinical validation or NASA certification. Current implemented features are described in the [README](README.md).

---

## 1. Cognitive Performance & Vigilance Monitoring (PVT Methodology)

* **The Problem:** During long-duration space missions, astronauts face microgravity, heavy operational workloads, and disrupted sleep schedules. These factors significantly impact reaction time, sustained attention, and cognitive agility.
* **NASA Standard:** NASA's Human Research Program (HRP) actively tracks cognitive and behavioral health risks. One of the primary tools used in spaceflight is the **Psychomotor Vigilance Test (PVT)**—a rapid, reaction-time task proven sensitive to fatigue and sleep loss.
* **Our Approach:** Zuma provides four experimental games and retains a separate legacy reaction/memory protocol. These tasks are not a validated PVT implementation.
* **Official Sources & References:**
  * [NASA Human Research Program (HRP): Risk of Adverse Cognitive or Behavioral Conditions](https://www.nasa.gov/hrp/)
  * Dinges, D. F., & Powell, J. W. (1985). *Microcomputer analyses of performance on a portable, simple visual RT task during sustained operations*. Behavior Research Methods, Instruments, & Computers.

---

## 2. Sleep Deprivation & Circadian Rhythm Disruption

* **The Problem:** On the International Space Station (ISS), astronauts experience 16 sunrises and sunsets every 24 hours, disrupting natural circadian rhythms and frequently leading to sleep restriction and cumulative fatigue.
* **NASA Standard:** Continuous monitoring of physiological metrics (such as resting heart rate and sleep duration) helps predict fatigue-related risks before they compromise mission safety.
* **Our Approach:** Users enter their sleep duration in a survey. Watch integration was removed from scope; Zuma does not collect heart-rate telemetry.
* **Official Sources & References:**
  * [NASA Task Book (Space Life Sciences): Circadian and Sleep Research on the ISS](https://taskbook.nasaprs.com/)
  * Czeisler, C. A., et al. (2015). *Sleep and circadian rhythms in space flight*.

---

## 3. Stress & Heart Rate Variability (HRV)

* **The Problem:** High-stakes space operations, isolation, and confinement elevate psychological and physiological stress levels, which require objective, non-invasive monitoring.
* **NASA Standard:** Heart Rate Variability (HRV) and resting heart rate trends serve as reliable, non-invasive biomarkers of autonomic nervous system balance and acute stress.
* **Our Approach:** Users self-report stress, fatigue, and mood. The application stores these answers and displays descriptive trends; it does not measure HRV or detect biometric anomalies.
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
| **Cognitive Fatigue & Attention Loss** | Psychomotor Vigilance Test (PVT) | Experimental cognitive games; separate legacy protocol |
| **Circadian Rhythm Disruption** | Sleep & activity tracking | Self-reported sleep duration |
| **Psychological & Physical Stress** | Heart Rate Variability (HRV) | Self-reported stress and descriptive trends |
| **Deep-Space Communication Latency** | Autonomous crew support systems | Offline-first architecture & local on-device AI model |
