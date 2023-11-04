# Matlab-Instrument-Drivers

Matlab-Instrument-Drivers are MATLAB classes that allows your MATLAB codes to controll various experimental instruments. 
This program requires the Instrument Control Toolbox.
More instruments will be added as the number of devices in our laboratory increases.

# Compatible Instrument List

## Oscilloscope `MID_Infiniium`

* Infiniium oscilloscopes that have the 5.00 or greater user interface software
    * S-Series oscilloscopes
    * V-Series oscilloscopes
    * Z-Series oscilloscopes
    * 9000 Series oscilloscopes
    * 9000H Series oscilloscopes
    * 90000A Series oscilloscopes
    * 90000 Q Series oscilloscopes
    * 90000 X Series oscilloscopes
* Infiniium oscilloscopes that have the 11.00 or greater user interface software
    * MXR-Series oscilloscopes
    * EXR-Series oscilloscopes (The author tested in this oscilloscope)

## Melec Stepping motor controller `MID_CV87x`

* Melec stepping motor controller C-V870 series
	* Note: the motor controllers are used in the the scanner of Insight K.K. for ultrasonic C-scan.

## Keysight waveform generator `33500/33600 Series`

* 33500 Series
* 33600 Series

## RITEC Pulser-Receiver `RPR-4000`

* RITEC RPR-4000

# Features

This driver set does not implement all the functions of the experimental instruments. 
The goal is to minimize the code written by the user by providing only the necessary functions.

# Demo

## Oscilloscope `MID-Infiniium`
See demo_oscilloscope.m

You can get waveforms displayed on your oscilloscope by:
```Matlab: Read waveforms from oscilloscope
devlist = visadevlist                          % Get available device list.
dev = devlist(1,:);                            % If the oscilloscope's index is 1 in the list. 
osc = MID_Infiniium(dev.ResourceName);         % Make handler of the oscilloscope from the VISA ResourceName.
[timevec, waveforms, info] = osc.getWaveform();% Acquire waveform from the signal source and fetch the waveform data from the oscilloscope.
plot(timevec, waveforms);
```
## Stepping motor controller `MID-CV87x`

The motorized stages can be used by:
```Matlab: Drive the motorized stage
PS = MID_CV87x();
PS.driveAbs('X',-30, 'Y', -30, 'Z', 30,'R', 30); % move to (X, Y, Z, R) = (-30, -30, 30, 30 )
```

# Requirement
 
* Mathworks Matlab 2022a
* Mathworks Matlab Instrument Control Toolbox
* VISA compatible for Instrument Control Toolbox (Keysight IO Library Suite (IOLS) 2022 Update 2 is recommended) 

For C-V87x Linear actuator
* MinGW -w64 compiler

# Installation

1. Install VISA software (Keysight IO Library Suite (IOLS) is recommended).
2. Copy the contents of "instrument-drivers" folder to the folder that your script/function exists.
 
# Usage

1. Connect the compatible instrument(s) to your computer.
2. Run demo_oscilloscope.m to see the demonstration. 
 
# Tests

## Oscilloscope `MID-Infiniium`

Tested on Keysight EXR054A.
 
## Stepping motor controller `MID-CV87x`

Tested on Melec C-V872.


# Author
 
* Naoki MATSUDA
* University of Fukui
* nmatsuda@u-fukui.ac.jp
 
# License
 
"Matlab-Instrument-Drivers" is under [MIT license](https://en.wikipedia.org/wiki/MIT_License).
 