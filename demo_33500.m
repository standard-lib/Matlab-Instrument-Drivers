clear fgen

fgen = MID_33500('TCPIP0::169.254.5.21::inst0::INSTR');

srate = 100e6;
timevec = -25e-6:(1/srate):25e-6;
sigma = 10e-6;
freq1 = 4e6;
freq2 = 6e6;
waveform1 = exp(-(timevec/sigma).^2).*cos(2*pi*freq1*timevec);
waveform2 = exp(-(timevec/sigma).^2).*cos(2*pi*freq2*timevec);

fgen.setArbWaveform(1, waveform1, srate);
fgen.setArbWaveform(2, waveform2, srate);


clear fgen
