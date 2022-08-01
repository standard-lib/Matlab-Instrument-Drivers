clear all
devlist = visadevlist
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

osc = MID_Infiniium(dev.ResourceName);
[timevec, waveforms, info] = osc.getWaveform();

% Display waveforms and channel infomation
plot(timevec, waveforms)
info(1) 
