%% class for Keysight Waveform Generator
classdef MID_33500 < handle
    
	properties (SetAccess = public)
        version = 1.1;
		vObj;   % visadevオブジェクト
        deviceModel
        flgDebug
    end
    
	methods
%%  コンストラクタ、デストラクタ
        % コンストラクタ
		% 引数でVISAアドレスを指定する．
        % また，buffersizeオプションで出力バッファサイズ，
        % timeoutオプションでタイムアウト時間を指定する。指定しない場合、それぞれ400MB，10秒になる。
        function obj = MID_33500(visaaddr, NameValueArgs)
            arguments
                visaaddr char
                NameValueArgs.buffersize double {mustBeInteger,mustBePositive} = 400e6
                NameValueArgs.timeout {mustBeInteger} = 10
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
        % デストラクタ
        function delete(obj)
            clear obj.vObj;
            fprintf('%s waveform generator was successfully closed\n', obj.deviceModel);
        end

%%  メソッド（波形送信）
        
        function setArbWaveform(obj, channel, waveform, srate)
            arguments
                obj 
                channel {mustBeMember(channel,{1,2})}
                waveform (1,:) {mustBeNumeric,mustBeReal}
                srate (1,1) {mustBeNumeric,mustBeReal}
            end
            specify_volt = max(abs(waveform));
            normalized_waveform = waveform / specify_volt;
            writeline(obj.vObj,sprintf('SOURce%d:DATA:VOLatile:CLEar', channel));
            % Set instrument's byte order to swap endian format (little
            % endian format)
            fprintf(obj.vObj, 'FORM:BORD SWAP'); % swap the endian format
            % Convert waveform data (float) to byte array (uint8). 
            % assume that system is little endian.
            uint8Waveform = typecast(single(normalized_waveform),'uint8');
            % make IEEE header (ex. '#520004')
            sizeStr = num2str(numel(uint8Waveform));
            lenSizeStr = num2str(numel(sizeStr));
            headerString = sprintf('SOUR%d:DATA:ARB auto%d,#%s%s', channel, channel, lenSizeStr, sizeStr);
            uint8Header = uint8(char(headerString));
            % Send header and data
            write(obj.vObj,[uint8Header uint8Waveform], "uint8");
            obj.assertError();
            writeline(obj.vObj,'*WAI');
            writeline(obj.vObj,sprintf('SOUR%d:FUNCtion:ARBitrary auto%d', channel, channel)); % set current arb waveform to defined arb pulse
            writeline(obj.vObj,sprintf('SOUR%d:FUNCtion ARB', channel)); % turn on arb function
            writeline(obj.vObj,sprintf('SOUR%d:VOLT %e', channel, specify_volt)); % set max waveform amplitude
            writeline(obj.vObj,sprintf('SOUR%d:VOLT:OFFSET 0', channel)); % set offset to 0 V            
            writeline(obj.vObj,sprintf('SOUR%d:FUNC:ARB:SRAT %e', channel, srate)); % set sample rate
            obj.assertError();
        end
        
        %%  メソッド（動作関係）
                
        function outputOn(obj, channel)
            writeline(obj.vObj, sprintf('OUTPUT%d ON', channel))
        end
  
        function outputOff(obj, channel)
            writeline(obj.vObj, sprintf('OUTPUT%d OFF', channel))
        end
        
        %%  メソッド（ルーチン）
        function assertError(obj)
            [exist, errorStr] = obj.queryError();
            if ~exist
               fprintf ('Arbitrary waveform generated without any error \n')
            else
               fprintf(['delete:', char(errorStr)])
               obj.clearError();
               error('assert failed')
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
				
		
		
		