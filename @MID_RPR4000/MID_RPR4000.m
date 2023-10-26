classdef MID_RPR4000 < handle
    %RPR4000 Ritec高出力パルサーレシーバーの制御クラス
    %   Sample program 
    %  %demo_RPR4000.m
    % clear rpr
    % % make handler
    % rpr = MID_RPR4000('Prolific'); % default:safemode = true, debugmode = false
    % rpr.setFrequencyAndCycle(1e6,9);
    % rpr.setFrequency(2e6);
    % rpr.setCycle(5);
    % rpr.setControl(1);
    % rpr.setRepRate(50.0);
    % freq = rpr.queryFrequency()
    % cycle = rpr.queryCycle()
    % control = rpr.queryControl()
    % repRate = rpr.queryRepRate()
    % clear rpr

    
    properties
        serialObj;
        flgDebug;
        flgSafeMode;
        RR_list = [10000 8000 5000 4000 2500 2000 1600 1200 1000 800 500 400 ...
            250 200 160 125 100 80 50 40 25 20 ...
            16 12 10 8 5 4 2.5 2 1.6 1.25 1 ...
            0.8 0.5 0.4 0.25 0.2 0.16 0.125 0.1 0.8];
        retries = 3;
        maxDutyRatio = 0.001;
    end
    
    methods
        function inst = MID_RPR4000(portname, NameValueArgs)
            % RPR4000の制御を行うクラスのコンストラクタ。
            %   portname: string/char: PnPNameか，COM番号：
            % 　PnPNameは接続に用いているUSB-シリアルアダプタのPnP entity nameの一部を入れる。
            %   デバイスマネージャに表示されている名前を入れればよい。'Prolific'など．
            %   COM番号は'COM3'など
            %   
            arguments
                portname char
                NameValueArgs.safemode logical = true
                NameValueArgs.debugmode logical = false
            end
            portList = MID_RPR4000.GetSerialPortByName(portname);
            if(numel(portList)==0)
                portStr = input('Input port number (ex.''COM13''):');
            else
                portStr = portList{1};% 同じものが二つ以上のアダプタでマッチしてしまったら，最初に見つかったものを選ぶ．
            end
            if( isempty(portList{1}) )
                portStr = portname;
            end
            inst.serialObj = serialport(portStr, 57600, 'Parity', 'none', 'DataBits', 8, 'StopBits', 1, 'FlowControl', 'hardware');
            configureTerminator(inst.serialObj, "CR");            
            fprintf('RPR4000 pulser/reciever was successifully opened\n');
            inst.flgSafeMode = NameValueArgs.safemode;
            inst.flgDebug = NameValueArgs.debugmode;
        end
        function waitForSend( inst )
            %CTSが１であることを確認．Matlab R2019以上で使用可能
            while( true ) 
                status = getpinstatus(inst.serialObj);
                if(status.ClearToSend == 1)
                    break;
                end
                pause(0.1);
            end
        end
        function [answer] = sendMessage( inst, message)
            count = 0;
            %fprintf('sendMessage: try to send %s\n', message);
            while(true)
                try
                    flush( inst.serialObj );
                    inst.waitForSend();
                    pause(0.1); %RPR4000がUpdateモードの場合、1秒に20コマンド以上は送れない。最低0.05秒待たなければならない。余裕をもって0.1秒待つ。
                    writeline( inst.serialObj, message );
                    answer = readline( inst.serialObj ); % 全てのコマンドに対してcall backが必ずある. queryならもちろんある．
                    pause(0.1); %バッファに残りがないかをチェックする前に少し待つ．
                    while(inst.serialObj.NumBytesAvailable > 0)
                        answer = join([answer, readline( inst.serialObj )]);
                        pause(0.1); %バッファに残りがないかをチェックする前に少し待つ．
                    end
                    break;
                catch exception
                    % エラーが起きた場合、10回施行して、それでもだめならあきらめる
                    fprintf('MID_RPR4000:sendMessage Error detected retry. count %d\n', count );
                    fprintf('pinstatus:\n')
                    getpinstatus(inst.serialObj)
                    count = count + 1;
                    pause(0.1);
                    if(count >= 10)
                        rethrow(exception)
                    end
                end
            end
            if( inst.flgDebug ) 
                fprintf('sendMessage():sent \"%s\"\n', message );
                fprintf('sendMessage():answer is \"%s\"\n', answer);
            end
        end
        function echo = generalCall(inst, message, echoPattern)
            %messageを送り，echoPatternに一致する返答が来るまで，何度もメッセージを送る．
            for count = 1:inst.retries
                ansStr = sendMessage(inst, message);
                if(contains(ansStr, echoPattern))
                    break;
                else
                    warning('echo %s does not match the pattern %s, retry (%d/10)\n', ansStr, char(string(echoPattern)), count);
                end
            end
            if(count == inst.retries)
                throw(MException('MID_RPR4000:generalCall', 'RPR4000 does not respond message %s .', message));
            end
            echo = extract(ansStr, echoPattern);
        end
        
        function setFrequencyAndCycle(inst, freq, cycle)
            % duty比がオーバーしないように，周波数・サイクルを変える．
            cycle = round(cycle);
            if(inst.flgSafeMode) %設定値の組み合わせでオーバーしていないかをチェックする．
                repRate = inst.queryRepRate();
                if(~inst.isAppropriateDutyRatio(freq, cycle, repRate))
                    error('Frequency %fMHz and cycle %d will exceed the duty ratio limit(%f). Set smaller cycle.', freq/1e6, cycle, inst.maxDutyRatio);
                end
            end
            inst.setCycle(0);
            inst.setFrequency(freq);
            inst.setCycle(cycle);
        end

        function [tf] = isAppropriateDutyRatio(inst, freq, cycle, repRate)
            % freqは０に設定することがある．この場合は無条件にOK
            tf = freq == 0 || freq*inst.maxDutyRatio > cycle*repRate;
        end
        function setFrequency(inst, freq)
            if(freq < 0 || freq > 21999999)
                error('frequency exceed');
            end
            if(inst.flgSafeMode)
                cycle = inst.queryCycle();
                repRate = inst.queryRepRate();
                if(~inst.isAppropriateDutyRatio(freq, cycle, repRate))
                    warning('Frequency %fMHz will exceed the duty ratio limit(%f). Program set cycle to 0.', freq/1e6, inst.maxDutyRatio);
                    inst.setCycle(0);
                end
            end

            freqInMHz = freq/1e6; % RPR4000に入れるときは、MHz単位なため
            callBackFreq = inst.callFrequency(['FR:', num2str(freqInMHz, '%09.6f') ]);
            if(abs(callBackFreq - freqInMHz) > 2)
                warning("setFrequency: Discrepancy in the setting value. The value specified is %f, but the value actually used is %f.", freqInMHz, callBackFreq);
            end
        end
        function [freq] = queryFrequency(inst)
            callBackFreq = inst.callFrequency('FR:?');
            freq = callBackFreq * 1e6;
        end
        function freq = callFrequency(inst, message)
            numPattern = digitsPattern(2) + "." + digitsPattern(6);
            preamblePattern = "FR:";
            echoPattern =  preamblePattern + numPattern;
            echoStr = inst.generalCall(message, echoPattern);
            freq = str2double(extract(extractAfter(echoStr,preamblePattern),numPattern));
        end

        function setCycle(inst, cycle)
            cycle = round(cycle);
            if(cycle < 0 || cycle > 4444 ) 
                error('cycles exceed');
            end
            if(inst.flgSafeMode)
                freq = inst.queryFrequency();
                repRate = inst.queryRepRate();
                if(~inst.isAppropriateDutyRatio(freq, cycle, repRate))
                    error('Cycle %d will exceed the duty ratio limit(%f). Set smaller cycle.', cycle, inst.maxDutyRatio);
                end
            end
            callBackCycle = inst.callCycle(['CY:', num2str(cycle, '%04d') ]);
            if(callBackCycle ~= cycle)
                warning("setCycle: Discrepancy in the setting value. The value specified is %f, but the value actually used is %f.", cycle, callBackCycle);
            end
        end
        function [cycle] = queryCycle( inst )
            cycle = inst.callCycle('CY:?');
        end

        function cycle = callCycle(inst, message)
            numPattern = digitsPattern(4);
            preamblePattern = "CY:";
            echoPattern =  preamblePattern + numPattern;
            echoStr = inst.generalCall(message, echoPattern);
            cycle = round(str2double(extract(extractAfter(echoStr,preamblePattern),numPattern)));
        end
        
        function setControl(inst, control)
            if(control < 0 || control > 100 ) 
                error('control exceed');
            end
            callBackControl = inst.callControl(['CO:', num2str(control, '%03d') ]);
            if(callBackControl ~= control)
                warning("setControl: Discrepancy in the setting value. The value specified is %f, but the value actually used is %f.", control, callBackControl);
            end
        end
        function [control] = queryControl( inst )
            control = inst.callControl('CO:?');
        end

        function control = callControl(inst, message)
            numPattern = digitsPattern(3);
            preamblePattern = "CO:";
            echoPattern =  preamblePattern + numPattern;
            echoStr = inst.generalCall(message, echoPattern);
            control = round(str2double(extract(extractAfter(echoStr,preamblePattern),numPattern)));
        end

        function setRepRate(inst, repRate)
            if(repRate < 0.08 || repRate > 10000 ) 
                error('Rep Rate exceed');
            end
            [~,index] = min(abs(inst.RR_list - repRate));
            specifyRepRate = inst.RR_list(index);
            if( abs(repRate - specifyRepRate) / specifyRepRate > 0.001 )
                warning("setRepRate: Rep. Rate %fHz is not in table. %fHz is used instead.", repRate, specifyRepRate);
            end
            repRate = specifyRepRate;
            if(inst.flgSafeMode)
                freq = inst.queryFrequency();
                cycle = inst.queryCycle();
                if(~inst.isAppropriateDutyRatio(freq, cycle, repRate))
                    error('RepRate %f will exceed the duty ratio limit(%f). Set smaller Rep. Rate.', repRate, inst.maxDutyRatio);
                end
            end
            callBackRepRate = inst.callRepRate(['RR:', num2str(repRate, '%09.3f') ]);
            if(callBackRepRate ~= repRate)
                warning("setRepRate: Discrepancy in the setting value. The value specified is %f, but the value actually used is %f.", repRate, callBackRepRate);
            end
        end
        function [repRate] = queryRepRate( inst )
            repRate = inst.callRepRate('RR:?');
        end

        function repRate = callRepRate(inst, message)
            numPattern = digitsPattern(5) + "." + digitsPattern(3);
            preamblePattern = "RR:";
            echoPattern =  preamblePattern + numPattern;
            echoStr = inst.generalCall(message, echoPattern);
            repRate = str2double(extract(extractAfter(echoStr,preamblePattern),numPattern));
        end

        function delete(stp)
            delete(stp.serialObj);
            fprintf('RPR4000 pulser/reciever was successifully closed\n');
        end
    end
    methods(Static)
        function [ portList ] = GetSerialPortByName( PnPEntityName )
            %getSerialPortByName PnP Entity name
            %PnP Entity Name(デバイスマネージャでみられる名前）と一致するポート番号(COM1~COM256)のリストを返す。
            %   .NETの機能を使う上、Windowに強く依存した場所を読みに行くので、Windowsじゃないとほとんど動く見込みなし。
            %   PnPEntityName: 検索したいポートが持っているPnP Entity nameを与える。正規表現が使える。
            %   portList: 検索に引っかかったポート番号をn行1列のセル配列に入れて返す。
            try
                NET.addAssembly('System.Management');
                manageClass = System.Management.ManagementClass('Win32_PnpEntity');
                manageObjectCollection = manageClass.GetInstances();
                manageObjectCollectionIterator = manageObjectCollection.GetEnumerator();
                manageObjectCollectionIterator.Reset();
                cnter = 1;
                portList = cell(1);
                for i=1:manageObjectCollection.Count+1
                    manageObjectCollectionIterator.MoveNext();
                    manageObject = manageObjectCollectionIterator.Current;
                    name = char(manageObject.GetPropertyValue('Name'));
                    if(~isempty( regexp( name,'\(COM[1-9][0-9]?[0-9]?\)','ONCE') ) && ...
                       ~isempty( regexp( name, PnPEntityName, 'ONCE')) )
                        matchStr = regexp( name, '\(COM[1-9][0-9]?[0-9]?\)', 'match');
                        comName = matchStr{1,1};
                        comName = comName(2:numel(comName)-1);
                        portList{cnter, 1 } = comName;
                        cnter = cnter + 1;
                    end
                end
            catch err
                fprintf('.NET system is not available.');
                portList = [];
            end
        end
    end
end