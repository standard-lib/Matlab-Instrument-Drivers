%% class for Keysight Waveform Generator
classdef MID_33500 < handle
    
	properties (SetAccess = public)
        version = 1.1;
		vObj;   % visadev�I�u�W�F�N�g
        deviceModel
        flgDebug
    end
    
	methods
%%  �R���X�g���N�^�A�f�X�g���N�^
        % �R���X�g���N�^
		% ������VISA�A�h���X���w�肷��D
        % �܂��Cbuffersize�I�v�V�����ŏo�̓o�b�t�@�T�C�Y�C
        % timeout�I�v�V�����Ń^�C���A�E�g���Ԃ��w�肷��B�w�肵�Ȃ��ꍇ�A���ꂼ��100��B�C10�b�ɂȂ�B
        function obj = MID_33500(visaaddr, NameValueArgs)
            arguments
                visaaddr char
                NameValueArgs.buffersize double = 1e6
                NameValueArgs.timeout double = 10
                NameValueArgs.debugmode logical = false
            end
            visaaddr = convertStringsToChars(visaaddr);

			obj.vObj = visadev(visaaddr);
			set(obj.vObj, 'OutputBufferSize', NameValueArgs.buffersize);
			set(obj.vObj, 'timeout', NameValueArgs.timeout);
            obj.deviceModel = obj.vObj.Model;
            fprintf('%s waveform generator was successfully opened\n', obj.deviceModel);
            obj.flgDebug = NameValueArgs.debugmode;
            obj.clearError();
        end
        % �f�X�g���N�^
        function delete(obj)
            clear obj.vObj;
            fprintf('%s waveform generator was successfully closed\n', obj.deviceModel);
        end

%%  ���\�b�h�i�g�`���M�j
        
        function setArbWaveform(obj, channel, waveform, srate)
            fgen = obj.vObj;
            specify_volt = max(abs(waveform));
            normalized_waveform = waveform / specify_volt;
            obj.assertError();
        	writeline(fgen,sprintf('SOURce%d:DATA:VOLatile:CLEar', channel));
            sizeStr = num2str(numel(waveform));
            sizeSizeStr = num2str(numel(sizeStr));
            headerString = sprintf(['SOUR%d:DATA:ARB auto%d,#', sizeSizeStr, sizeStr], channel, channel);
            write(fgen,headerString, "char");
            writebinblock(fgen,normalized_waveform,"single");
%             arbstring = sprintf('SOUR%d:DATA:ARB auto%d %s', channel, channel,  num2str(normalized_waveform,',%.5f'));
% 	        writeline(fgen,arbstring);
            obj.assertError();
            writeline(fgen,'*WAI');
            writeline(fgen,sprintf('SOUR%d:FUNCtion:ARBitrary auto%d', channel, channel)); % set current arb waveform to defined arb pulse
            writeline(fgen,sprintf('SOUR%d:FUNCtion ARB', channel)); % turn on arb function
            writeline(fgen,sprintf('SOUR%d:VOLT %e', channel, specify_volt)); % set max waveform amplitude
            writeline(fgen,sprintf('SOUR%d:VOLT:OFFSET 0', channel)); % set offset to 0 V            
            writeline(fgen,sprintf('SOUR%d:FUNC:ARB:SRAT %e', channel, srate)); % set sample rate
            obj.assertError();
        end
        
        %%  ���\�b�h�i����֌W�j
                
        function outputOn(obj, channel)
            writeline(obj.vObj, sprintf('OUTPUT%d ON', channel))
        end
  
        function outputOff(obj, channel)
            writeline(obj.vObj, sprintf('OUTPUT%d OFF', channel))
        end
        
        %%  ���\�b�h�i���[�`���j
        function assertError(obj)
            [exist, errorStr] = obj.queryError();
            if ~exist
               fprintf ('Arbitrary waveform generated without any error \n')
            else
               error (['Error reported: ', char(errorStr)])
            end
        end
        function clearError(obj)
            [exist, msg] = obj.queryError();
            fprintf(['delete:', char(msg)])
            while(exist)
                [exist, msg] = obj.queryError();
                fprintf(['delete:', char(msg)])
            end
        end
        function [errorExists, errorStr] = queryError(obj)
            % error checking
            writeline(obj.vObj, 'SYST:ERR?');
            errorStr = readline (obj.vObj);
            errorExists = ~strncmp (errorStr, '+0,"No error"',13);
        end
    end
end
				
		
		
		