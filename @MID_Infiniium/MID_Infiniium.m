%% �I�V���X�R�[�vInfiniium DSOS054A�𓮂������߂̃N���X
	% ���\�b�h�̏ڍׂ͈ȉ��ɋL�q
    %   2015/02/27�F�ǂ݂Ƃ�`����WORD�ɕύX
    %   2016/07/13: ���c�ҏW�B�l�ԑ��쒆�S�֕ύX�A�v���O�����̊ȑf���Aquery INTERRUPT�G���[�ւ̑Ή�
classdef MID_Infiniium < handle
    
	properties (SetAccess = public)
        DriverVer = 1.0;
		vObj;   % visa�I�u�W�F�N�g
        deviceModel;
        OscSoftwareVerStr;
        OscSoftwareVerNum;
        bufferSize;
        numChannel = 4;  % ���ׂẴ`�����l����
    end
    
	methods
%%  �R���X�g���N�^�A�f�X�g���N�^
        % �I�V���X�R�[�vDSOS054A�̃R���X�g���N�^
		% �����œ��̓o�b�t�@�����w�肷��B�w�肵�Ȃ��ꍇ�A1MB���x�ɂȂ�B
        function obj = MID_Infiniium(visaaddr, varargin)
            visaaddr = convertStringsToChars(visaaddr);
			p = inputParser;
            defaultBufferSize = 1e6;
            addRequired(p, 'visaaddress', @ischar);
            addParameter(p, 'buffersize', defaultBufferSize, @isnumeric);
            parse(p,visaaddr,varargin{:})

			obj.vObj = visadev(p.Results.visaaddress);
			set(obj.vObj, 'InputBufferSize', p.Results.buffersize);
            obj.bufferSize = get(obj.vObj, 'InputBufferSize');
            obj.deviceModel = obj.vObj.Model;
            fprintf('%s oscilloscope was successfully opened\n', obj.deviceModel);
            splittedIDN = strsplit(obj.queryIDN(), ',');
            obj.OscSoftwareVerStr = splittedIDN(4);
            splittedVersionStr = strsplit(splittedIDN(4), '.');
            obj.OscSoftwareVerNum = str2double(strcat(splittedVersionStr(1),'.',splittedVersionStr(2)));
        end
        % �I�V���X�R�[�vDSOS054A�̃f�X�g���N�^
        function delete(obj)
            if( strcmpi( get(obj.vObj, 'Status'), 'open'))
                sendMessage(obj, ':RUN');
%                 fclose(obj.vObj);
            end
            clear obj.vObj;
            fprintf('%s oscilloscope was successfully closed\n', obj.deviceModel);
        end

%%  ���\�b�h�i�g�`�f�[�^�擾�j
        function [timevec, waveform, info] = getWaveform(obj, varargin)
            acquireSingle(obj);
            waveform = zeros( obj.numChannel, 1 );
            for idxChannel=1:obj.numChannel
                state = sendQuery( obj, sprintf(':CHAN%d:DISP?', idxChannel) );
                if( state(1) == '1')
                    [ single_timevec, single_waveform ] = readWaveform( obj, idxChannel );

                    waveform( idxChannel, 1:numel(single_waveform) ) = single_waveform;
                    timevec = single_timevec;
                end
                if( idxChannel == 1 )
                    info = getInfo( obj, idxChannel );
                else
                    info = [info; getInfo( obj, idxChannel )];
                end
            end
        end
        
        % root level�̃R�}���h�͐���ɓ����Ȃ��ꍇ�����邽�߁A�O�̂��߉��̃��\�b�h�����s����
        function autoScale(obj, channel)
            flgAverage = queryAvgMode(obj); %�ꎞ�I��Averaging���[�h��؂邽�߁AAverage�����Ă������ǂ������L�����Ă���
            setAvg(obj, 'OFF');
            count = 0;
            while (1)
                acquireSingle(obj);
                [~, tempWaveform] = readWaveform(obj, channel);
                [range, offset] = queryRangeOffset(obj, channel);
                waveformMax = max( tempWaveform(:) );
                waveformMin = min( tempWaveform(:) );
                tMax = max( [waveformMax, 0] );
                tMin = min( [waveformMin, 0] );
                
                hRange = range/2.0;
                uAmp = waveformMax - offset;
                lAmp = waveformMin - offset;
                if ( (hRange*0.95 > uAmp) && (-hRange*0.95 < lAmp) )
                    % �g�`�������W���Ɋ܂܂��ꍇ
                    if ( (hRange*0.75 < uAmp) && (-hRange*0.75 > lAmp) )
                        % �c���������̏㉺�[�Ɋ܂܂�Ă����OK�Ƃ���
                        break;
                    else
                        % �K���Ȕ{��
                        newRange = (tMax - tMin)/0.85;
                    end
                else
                    % �g�`���傫������i�����W����������j�ꍇ
                    % �K���Ȕ{��
                    newRange = (tMax - tMin)*2;
                end
                newOffset = (tMax + tMin)*0.5;
                setRangeOffset(obj, channel, newRange, newOffset);
                
                count = count + 1;
                if (count > 10)
                    fprintf('Error (autoScale): not completed\n');
                    return;
                end
            end
            if ( flgAverage )
                sendMessage(obj, 'ACQ:AVER ON');
            end
        end
  
        
%%  ���\�b�h�i���[�`���j
        function acquireSingle(obj)
            sendMessage(obj, ':STOP');
            sendQuery(obj,'*OPC?');
            sendQuery(obj, ':ADER?'); % Is this requied? must be :PDER? ?
            sendMessage(obj,':SING');
            fprintf('now acquiring');
            while( 0 == str2double( sendQuery(obj, ':ADER?')) )
                fprintf('.');
                pause(0.1);
            end
            fprintf(' done\n');
        end
        
        function [ timevec, waveform ] = readWaveform( obj, idxChannel )
            sendMessage( obj, sprintf(':WAV:SOUR CHAN%d', idxChannel) );
            %   �ǂ݂Ƃ�`���FWORD
            sendMessage(obj, ':WAV:FORM WORD');
            %   ���g���E�G���f�B�A��
            sendMessage(obj, ':WAV:BYT LSBF');
            % Preamble�̓ǂݍ���
            prem = sendQuery(obj, ':WAV:PRE?');
            premSp = strsplit(prem, ',');
            %             if ( str2num(char(premSp(1))) == 1 )
            %                 fprintf('   Format = BYTE');
            %             elseif ( str2num(char(premSp(1))) == 2 )
            %                 fprintf('   Format = WORD');
            %             end
            %             if ( str2num(char(premSp(2))) == 1 )
            %                 fprintf(' ---> Type = NORMal\n');
            %             end
            %             if ( str2num(char(premSp(2))) == 2 )
            %                 fprintf(' ---> Type = AVERage\n');
            %             end
            %     Num_Data_points = str2num(char(premSp(3));
            %     Average_Count = str2num(char(premSp(4));
            Xincrement    = str2double( char(premSp(5)) );
            Xorigin       = str2double( char(premSp(6)) );
            Xreference    = str2double( char(premSp(7)) );
            Yincrement    = str2double( char(premSp(8)) );
            Yorigin       = str2double( char(premSp(9)) );
            Yreference    = str2double( char(premSp(10) ));    

            sendMessage(obj, ':WAV:DATA?');
            % ���߂�2����(2�o�C�g)�𕄍��t8�r�b�g�����Ƃ��ēǂݍ��ށi#N�j
            precision = 'int8';
            preStr = read(obj.vObj, 2, precision);
            % N�����擾
            str_num = sscanf( char(preStr), '%*c%d' );
            % ������N���������ǂݍ���L���擾
            bytesStr = read(obj.vObj, str_num, precision);
            % scanBytes�̎擾
            scanBytes = str2double( char(bytesStr) );
                         % scanBytes��InputBufferSize�𒴂��Ȃ����ǂ����̊m�F
             if (scanBytes > obj.bufferSize)
                error('Input buffersize is smaller than that to read waveform.\nIncrease it. (use `buffersize` option)');
             end
            % �f�[�^�̓ǂݍ��݁iWORD�F8bit + 8bit = 16 bit�CLSB first�j
            precision = 'int16';
            temp = read(obj.vObj, scanBytes/2, precision);

            %terminal character �̓ǂݍ���
            %��������Ȃ��ƁA���̓o�b�t�@�ɒl���c��̂�query INTERRUPT��������
            [~] = read(obj.vObj, 1, 'char');
            waveform = (  double(temp)   - Yreference )*Yincrement + Yorigin;
            timevec  = ( (1:numel(temp))' - Xreference )*Xincrement + Xorigin;
        end
        
        function [info] = getInfo( obj, idxChannel )
            onoff = queryDisplayed( obj, idxChannel );
            if(  queryAvgMode(obj) )
                avgs = queryAvgs(obj);
            else
                avgs = 1;
            end
            points = queryPoints(obj);
            sRate = querySampRate(obj);
            impedance = queryImp( obj, idxChannel );
            trig_mode = queryTrigMode( obj );
            trig_source = queryTrigEdgeSource( obj );
            trig_slope = queryTrigEdgeSlope( obj );
            trig_level = queryTrigLevel( obj );
            
            info = struct('available', onoff, ...
                'averages', avgs,...
                'points', points, ...
                'sampling_rate', sRate,...
                'impedance', impedance,...
                'trigger_mode', trig_mode,...
                'trigger_source', trig_source,...
                'trigger_slope', trig_slope,...
                'trigger_level', trig_level);
        end
        
%%  ���\�b�h�i�₢���킹�j
        % �@�햼�̖₢���킹
        function IDN_str = queryIDN(obj)
            IDN_str= sendQuery( obj, '*IDN?' );
        end
        % Average���[�h�̖₢���킹
        function tfAvgMode = queryAvgMode(obj)
            if(  str2double( sendQuery(obj, ':ACQ:AVER?') ) == 0 )
                tfAvgMode = false;
            else
                tfAvgMode = true;
            end
        end
        % Average�񐔂̖₢���킹
        function averages = queryAvgs(obj)
            averages = str2double( sendQuery(obj, ':ACQuire:COUNt?') );
        end
        % ���݂̃f�[�^�_���̖₢���킹
        function points = queryPoints(obj)
            points = str2double( sendQuery(obj, ':ACQ:POIN?') );
        end
        % �T���v�����O���[�g�̖₢���킹
        function sRate = querySampRate(obj)
            sRate = str2double( sendQuery(obj, ':ACQ:SRAT?') );
        end
        % �`�����l���̃C���s�[�_���X�̎擾
        function impedance = queryImp(obj, channel)
            inputStr = sendQuery( obj, sprintf(':CHANnel%d:INPut?', channel) );
            if ( strcmp(inputStr, 'DC50') )
                impedance = 50.0;
            elseif ( strcmp(inputStr, 'DC') )
                impedance = 1e6;
            else
                fprintf('Input coupling: not DC\n');
            end
        end 
        % �w�肵���`�����l�������݂��邩�ǂ���
        function confChannel(obj, num)
            if (num > obj.numChannel)
                fprintf('Error: such channel does not exist\n');
            end
        end
        % �w�肵���`�����l�����\������Ă��邩�ǂ���
        function tfDisplayed = queryDisplayed(obj, idxChannel)
            obj.confChannel(idxChannel);
            state = sendQuery( obj, sprintf(':CHAN%d:DISP?', idxChannel) );
            if( state(1) == '1')
                tfDisplayed = true;
            else
                tfDisplayed = false;
            end
        end
        % �w�肵���`�����l���̏c���͈͂ƃI�t�Z�b�g���擾
        function [range, offset] = queryRangeOffset(obj, channel)
            range  = str2double( sendQuery( obj, sprintf('CHAN%d:RANG?', channel) ) );
            offset = str2double( sendQuery( obj, sprintf('CHAN%d:OFFS?', channel) ) );
        end
        function trig_mode = queryTrigMode(obj)
            trig_mode = sendQuery( obj,'TRIG:MODE?' ); 
        end
        function trig_edge_src = queryTrigEdgeSource( obj )
            trig_edge_src = sendQuery( obj, ':TRIG:EDGE:SOUR?');
        end
        function trig_edge_slope = queryTrigEdgeSlope( obj )
            trig_edge_slope = sendQuery( obj, ':TRIG:EDGE:SLOP?');
        end
        % �g���K���x���̎擾(AUX�̂�)
        function trig_level = queryTrigLevel(obj)
            trig_edge_src = queryTrigEdgeSource( obj );
            if( trig_edge_src(1) == 'C' || trig_edge_src(1) == 'A' )
                trig_level = str2double( sendQuery( obj, sprintf(':TRIG:LEV? %s', trig_edge_src )) );
            else
                trig_level = 0;
            end
            
        end
        
%%  ���\�b�h�i�l�ݒ�j
    %% Acquisition�֌W
        % Real time sampling mode �ւ̐ݒ�
        function setRTSamp(obj)
            sendMessage(obj, ':ACQuire:MODE RTIMe');
        end
        % Average�̐ݒ�B �����FON��OFF�A���ϓ_��(2�̗ݏ���w��)
        function setAvg(obj, varargin)
            for strInd = 1:numel(varargin)
                if ( strcmp(varargin{strInd}, 'ON') )
                    sendMessage(obj, ':ACQuire:AVERage ON');
                elseif ( strcmp(varargin{strInd}, 'OFF') )
                    sendMessage(obj, ':ACQuire:AVERage OFF');
                elseif ( isnumeric(varargin{strInd}) )
                    num = 2^nextpow2(varargin{strInd});
                    sendMessage(obj, sprintf(':ACQuire:AVERage:COUNt %d', num));
                end
            end
        end
        % Sampling rate�̐ݒ�
        function setSampRate(obj, rate)
            if ( strcmp(rate, 'AUTO') )
                sendMessage(obj, ':ACQuire:SRATe AUTO');
            else
                sendMessage( obj, sprintf(':ACQuire:SRATe %d', rate) );
            end
        end
        % ���������̐ݒ�B�����F'AUTO'�܂��͓_��
        function setPoints(obj, varargin)
            if ( strcmp(varargin{1}, 'AUTO') )
                sendMessage(obj, ':ACQ:POIN AUTO');
            else
                sendMessage(obj, sprintf(':ACQ:POIN %d', varargin{1}) );
            end
        end
        % High resolution mode�̐ݒ�B (����)setSamplingmode���ɂ���I�I�I
        function setHighRes(obj)
            sendMessage(obj, ':ACQuire:MODE HRESolution');
        end
        % Run�ɂ���
        function setRun(obj)
        end

    %% Channel�֌W
        % �w�肵���`�����l���̏c���͈͂ƃI�t�Z�b�g��ݒ�
        function setRangeOffset(obj, channel, range, offset)
            sendMessage( obj, sprintf(':CHAN%d:RANG %e', channel, range) );
            sendMessage( obj, sprintf(':CHAN%d:OFFS %e', channel, offset) );
        end
     
 
%%  �R�}���h���M�ƃN�G���[��M
    % �R�}���h���M
        function sendMessage(obj, message)
            count = 0;
            while (count < 10)
                try
                    writeline(obj.vObj, message);
                    break;
                catch exception
                    %�G���[��������10�񎎍s����B
                    fprintf('Error(sendMessage): retry. count%d\n', count);
                    count = count + 1;
                    pause(1);
                    if (count >= 10)
                        rethrow(exception);
                    end
                end
            end
        end
        % �N�G���[
        function answer = sendQuery(obj, message)
            if ( ~contains(message, '?') )
                fprintf('Error: the message is not a query!\n');
            else
                count = 0;
                while (count < 10)
                    try
                        answer = strtrim( writeread(obj.vObj, message) );
                        break;
                    catch exception
                        %�G���[��������10�񎎍s����B
                        fprintf('Error (sendQuery): retry. count%d\n', count);
                        count = count + 1;
                        pause(1);
                        if (count >= 10)
                            rethrow(exception);
                        end
                    end
                end
            end
        end 
    end
end
				
		
		
		