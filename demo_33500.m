clear fgen

fgen = MID_33500('TCPIP0::169.254.5.21::inst0::INSTR');

srate = 160e6;
timevec = -250e-6:(1/srate):250e-6;
sigma = 10e-6;
freq1 = 4e6;
freq2 = 6e6;
waveform1 = exp(-(timevec/sigma).^2).*cos(2*pi*freq1*timevec);
waveform2 = exp(-(timevec/sigma).^2).*cos(2*pi*freq2*timevec);

plot(timevec, waveform1, timevec, waveform2+2)


fgen.outputOff(1);
fgen.outputOff(2);
fgen.setArbWaveform(1, waveform1, srate);
fgen.setArbWaveform(2, waveform2, srate);
fgen.outputOn(1);
fgen.outputOn(2);


clear fgen
