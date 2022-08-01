# Matlab-Instrument-Drivers

`At present, this driver is under development.`

Matlab-Instrument-Drivers are codes that allows various experimental devices to be used from your Matlab program. This program requires the Instrument Control Toolbox.
More instruments will be added as the number of devices in our laboratory increases.

# Compatible Instrument list

## Oscilloscope `MID-Infiniium`

* Keysight Infiniium oscilloscope `MID-Infiniium class`
	* Infiniium oscilloscope that have the 5.00 or greater
		* S-Series oscilloscope
		* V-Series oscilloscope
		* Z-Series oscilloscope
		* 9000 Series oscilloscope
		* 9000H Series oscilloscope
		* 90000A Series oscilloscope
		* 90000 Q Series oscilloscope
		* 90000 X Series oscilloscope
	* Infiniium oscilloscope that have the 11.00 or greater
		* MXR-Series oscilloscope
		* EXR-Series oscilloscope (The author tested in this oscilloscope)


# Demo

## Oscilloscope `MID-Infiniium`

You can get waveforms from your oscilloscope by:
```Matlab: Read waveforms from oscilloscope
devlist = visadevlist                          % Get available device list.
dev = devlist(1,:);                            % If the oscilloscope's index is 1 in the list. 
osc = MID_Infiniium(dev.ResourceName);         % Make handler of the oscilloscope from the VISA ResourceName.
[timevec, waveforms, info] = osc.getWaveform();% Acquire waveform from the signal source and fetch the waveform data from the oscilloscope.
plot(timevec, waveforms);
```

# Features



# Requirement
 
* Mathworks Matlab 2022a
* Mathworks Matlab Instrument Control Toolbox
* VISA compatible for Instrument Control Toolbox (Keysight IO Library Suite (IOLS) 2022 Update 2 is Recommended) 

# Installation

Just copy the "instrument-drivers" folder to the folder that your script/function exists.
 
# Usage

1. Connect the compatible instrument(s) to your computer.
2. Run demo_oscilloscope.m to see the demonstration. 
 
# Tests

## Oscilloscope `MID-Infiniium`

The driver has been tested on Keysight EXR054A.
 
# Author
 
* Naoki MATSUDA
* University of Fukui
* nmatsuda@u-fukui.ac.jp
 
# License
 
"Matlab-Instrument-Drivers" is under [MIT license](https://en.wikipedia.org/wiki/MIT_License).
 