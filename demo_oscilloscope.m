clear all

% Get instrument list connected to this computer
devlist = visadevlist

% Select the device to connect
if(size(devlist,1) == 0 )
    fprintf('Device not found!');
    quit
elseif( size(devlist, 1)>1)
    while(true)
        idxdev = input(sprintf('%d device was found. Choose your oscilloscope number(1~%d):', size(devlist,1),  size(devlist,1)));
        if(idxdev >= 1 && idxdev <= size(devlist,1))
            break;
        end
    end
else
    idxdev = 1;
end
dev = devlist(idxdev,:);
fprintf('%s was selected\n', dev.Model);

% Get handler of the oscilloscope
osc = MID_Infiniium(dev.ResourceName);

% Make the oscilloscope aquire the signal. Fetch data from the oscilloscope
% to this computer.
[timevec, waveforms, info] = osc.getWaveform();

% Display waveforms and channel infomation
plot(timevec, waveforms)
info(1) % channel 1 infomations
