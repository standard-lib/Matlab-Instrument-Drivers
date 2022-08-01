%% オシロスコープInfiniium DSOS054Aを動かすためのクラス
	% メソッドの詳細は以下に記述
    %   2015/02/27：読みとり形式をWORDに変更
    %   2016/07/13: 松田編集。人間操作中心へ変更、プログラムの簡素化、query INTERRUPTエラーへの対応
classdef MID_Infiniium < handle
    
	properties (SetAccess = public)
        DriverVer = 1.0;
		vObj;   % visaオブジェクト
        deviceModel;
        OscSoftwareVerStr;
        OscSoftwareVerNum;
        bufferSize;
        numChannel = 4;  % すべてのチャンネル数
    end
    
	methods
%%  コンストラクタ、デストラクタ
        % オシロスコープDSOS054Aのコンストラクタ
		% 引数で入力バッファ数を指定する。指定しない場合、1MB程度になる。
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
        % オシロスコープDSOS054Aのデストラクタ
        function delete(obj)
            if( strcmpi( get(obj.vObj, 'Status'), 'open'))
                sendMessage(obj, ':RUN');
%                 fclose(obj.vObj);
            end
            clear obj.vObj;
            fprintf('%s oscilloscope was successfully closed\n', obj.deviceModel);
        end

%%  メソッド（波形データ取得）
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
        
        % root levelのコマンドは正常に働かない場合があるため、念のため下のメソッドも実行する
        function autoScale(obj, channel)
            flgAverage = queryAvgMode(obj); %一時的にAveragingモードを切るため、Averageがついていたかどうかを記憶しておく
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
                    % 波形がレンジ内に含まれる場合
                    if ( (hRange*0.75 < uAmp) && (-hRange*0.75 > lAmp) )
                        % 縦軸メモリの上下端に含まれていればOKとする
                        break;
                    else
                        % 適当な倍率
                        newRange = (tMax - tMin)/0.85;
                    end
                else
                    % 波形が大きすぎる（レンジが狭すぎる）場合
                    % 適当な倍率
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
  
        
%%  メソッド（ルーチン）
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
            %   読みとり形式：WORD
            sendMessage(obj, ':WAV:FORM WORD');
            %   リトル・エンディアン
            sendMessage(obj, ':WAV:BYT LSBF');
            % Preambleの読み込み
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
            % 初めの2文字(2バイト)を符号付8ビット整数として読み込む（#N）
            precision = 'int8';
            preStr = read(obj.vObj, 2, precision);
            % Nだけ取得
            str_num = sscanf( char(preStr), '%*c%d' );
            % 続けてN文字だけ読み込みLを取得
            bytesStr = read(obj.vObj, str_num, precision);
            % scanBytesの取得
            scanBytes = str2double( char(bytesStr) );
                         % scanBytesがInputBufferSizeを超えないかどうかの確認
             if (scanBytes > obj.bufferSize)
                error('Input buffersize is smaller than that to read waveform.\nIncrease it. (use `buffersize` option)');
             end
            % データの読み込み（WORD：8bit + 8bit = 16 bit，LSB first）
            precision = 'int16';
            temp = read(obj.vObj, scanBytes/2, precision);

            %terminal character の読み込み
            %これをしないと、入力バッファに値が残るのでquery INTERRUPTが生じる
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
        
%%  メソッド（問い合わせ）
        % 機種名の問い合わせ
        function IDN_str = queryIDN(obj)
            IDN_str= sendQuery( obj, '*IDN?' );
        end
        % Averageモードの問い合わせ
        function tfAvgMode = queryAvgMode(obj)
            if(  str2double( sendQuery(obj, ':ACQ:AVER?') ) == 0 )
                tfAvgMode = false;
            else
                tfAvgMode = true;
            end
        end
        % Average回数の問い合わせ
        function averages = queryAvgs(obj)
            averages = str2double( sendQuery(obj, ':ACQuire:COUNt?') );
        end
        % 現在のデータ点数の問い合わせ
        function points = queryPoints(obj)
            points = str2double( sendQuery(obj, ':ACQ:POIN?') );
        end
        % サンプリングレートの問い合わせ
        function sRate = querySampRate(obj)
            sRate = str2double( sendQuery(obj, ':ACQ:SRAT?') );
        end
        % チャンネルのインピーダンスの取得
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
        % 指定したチャンネルが存在するかどうか
        function confChannel(obj, num)
            if (num > obj.numChannel)
                fprintf('Error: such channel does not exist\n');
            end
        end
        % 指定したチャンネルが表示されているかどうか
        function tfDisplayed = queryDisplayed(obj, idxChannel)
            obj.confChannel(idxChannel);
            state = sendQuery( obj, sprintf(':CHAN%d:DISP?', idxChannel) );
            if( state(1) == '1')
                tfDisplayed = true;
            else
                tfDisplayed = false;
            end
        end
        % 指定したチャンネルの縦軸範囲とオフセットを取得
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
        % トリガレベルの取得(AUXのみ)
        function trig_level = queryTrigLevel(obj)
            trig_edge_src = queryTrigEdgeSource( obj );
            if( trig_edge_src(1) == 'C' || trig_edge_src(1) == 'A' )
                trig_level = str2double( sendQuery( obj, sprintf(':TRIG:LEV? %s', trig_edge_src )) );
            else
                trig_level = 0;
            end
            
        end
        
%%  メソッド（値設定）
    %% Acquisition関係
        % Real time sampling mode への設定
        function setRTSamp(obj)
            sendMessage(obj, ':ACQuire:MODE RTIMe');
        end
        % Averageの設定。 引数：ONかOFF、平均点数(2の累乗を指定)
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
        % Sampling rateの設定
        function setSampRate(obj, rate)
            if ( strcmp(rate, 'AUTO') )
                sendMessage(obj, ':ACQuire:SRATe AUTO');
            else
                sendMessage( obj, sprintf(':ACQuire:SRATe %d', rate) );
            end
        end
        % メモリ長の設定。引数：'AUTO'または点数
        function setPoints(obj, varargin)
            if ( strcmp(varargin{1}, 'AUTO') )
                sendMessage(obj, ':ACQ:POIN AUTO');
            else
                sendMessage(obj, sprintf(':ACQ:POIN %d', varargin{1}) );
            end
        end
        % High resolution modeの設定。 (注意)setSamplingmodeを先にする！！！
        function setHighRes(obj)
            sendMessage(obj, ':ACQuire:MODE HRESolution');
        end
        % Runにする
        function setRun(obj)
        end

    %% Channel関係
        % 指定したチャンネルの縦軸範囲とオフセットを設定
        function setRangeOffset(obj, channel, range, offset)
            sendMessage( obj, sprintf(':CHAN%d:RANG %e', channel, range) );
            sendMessage( obj, sprintf(':CHAN%d:OFFS %e', channel, offset) );
        end
     
 
%%  コマンド送信とクエリー受信
    % コマンド送信
        function sendMessage(obj, message)
            count = 0;
            while (count < 10)
                try
                    writeline(obj.vObj, message);
                    break;
                catch exception
                    %エラー発生時は10回試行する。
                    fprintf('Error(sendMessage): retry. count%d\n', count);
                    count = count + 1;
                    pause(1);
                    if (count >= 10)
                        rethrow(exception);
                    end
                end
            end
        end
        % クエリー
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
                        %エラー発生時は10回試行する。
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
				
		
		
		