# Matlab-Instrument-Drivers

`At present, this driver is under development.`

Matlab-Instrument-Drivers are codes that allows various experimental devices to be used from your Matlab program. This program requires the Instrument Control Toolbox.
More instruments will be added as the number of devices in our laboratory increases.

# Compatible Instrument list

* Keysight Infiniium oscilloscope `MID-Infiniium class`
	** S-Series oscilloscope
	** V-Series oscilloscope
	** Z-Series oscilloscope
	** 9000 Series oscilloscope
	** 9000H Series oscilloscope
	** 90000A Series oscilloscope
	** 90000 Q Series oscilloscope
	** 90000 X Series oscilloscope


# Demo


# Features
## Oscilloscope `MID-Infiniium`

You can get waveforms from your oscilloscope by:
```Matlab: Read waveforms from oscilloscope
devlist = visadevlist % Get available device list.
dev = devlist(1,:);   % If the oscilloscope is in the index 1. 
osc = MID_Infiniium(dev.ResourceName);         % Make handler of the oscilloscope from the VISA ResourceName such as "USB0::0x0699::0x036A::CU010105::0::INSTR"
[timevec, waveforms, info] = osc.getWaveform();% Acquire waveform from the signal source and transfer the waveform data to MATLAB

plot(timevec, waveforms);
```

# Requirement
 
* Mathworks Matlab 2022a
* Mathworks Matlab Instrument Control Toolbox
* VISA compatible for Instrument Control Toolbox (Keysight IO Library Suite (IOLS) 2022 Update 2 is Recommended) 

# Installation

Just copy the "instrument-drivers" folder to the folder that your script/function exists.
 
# Usage

1. Connect the compatible instrument(s) to your computer.
2. Run demo.m to see demonstration of the instrument-drivers. 
 
# Note
 

 
# Author
 
* Naoki MATSUDA
* University of Fukui
* nmatsuda@u-fukui.ac.jp
 
# License
 
"Matlab-Instrument-Drivers" is under [MIT license](https://en.wikipedia.org/wiki/MIT_License).
 