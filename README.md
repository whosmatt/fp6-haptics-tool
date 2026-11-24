# fp6-haptics-tool

This is a tool to design, simulate and test haptic waveforms on the Fairphone 6, and output them in a format suitable for the Awinic AW86938 driver. It is designed around the specific limitations and features of this chip family.  
Measurement of the FP6 LRA response and Q works well enough (validated by external high bandwidth IMU) via the microphone that the external accelerometer measurement was ommitted in this repo. The measurements are used to predict and generate braking waveforms.  
The tool shows reference waveforms, mostly to get a better idea of what the often vague haptic effect descriptions are supposed to be. Waveforms from the pixel 3 and pixel 9 were used, but they are not included here due to the unclear license.

If you are interested in live testing:  
Copy and fill `hapkit.local.env.example` to `hapkit.local.env`.  
On-device testing is not designed with cleanup in mind.

---

This repo is almost entirely LLM generated, use at your own risk. The resulting output file and table are easy to verify by hand.
