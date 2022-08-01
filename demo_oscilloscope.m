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
fprintf('%s was selected', dev.Model);

osc = MID_Infiniium();
[timevec, waveform, info] = osc.getWaveform();

% Display waveforms and channel infomation
plot(timevec, waveform(1,:), timevec, waveform(2,:), timevec, waveform(3,:), timevec, waveform(4,:));
info(1) 
