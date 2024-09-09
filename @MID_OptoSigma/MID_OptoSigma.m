classdef MID_OptoSigma < handle
    %Class for OptoSigma stage controller
    % History:
    % 2024/9/6 Written by N.Matsuda.

    properties
        serialObj;
        flgDebug;
        controllerName;
        maxAxes;
        mmperfullpulse = [4e-4, 4e-4]; %unit mm 製品の
        divides;
        axes;
        baudrate;
        e_max_pps = 500000;  % electrical maximum velocity (pulse/s)
        e_maxR_ms = 1000;   % electrical maximum of rising time (ms)
        m_strt_mmps = 0.4;  % starting velocity (mm/s)
        m_max_mmps2 = 180; % maximum acceleration (mm/s^2)
        m_max_mmps = 40;  % maximum velocity (mm/s);
        version = 0.0;

    end
    
    methods
        function inst = MID_OptoSigma(portname, NameValueArgs)
            %MID_OPTOSIGMA 
            %   constructor of MID_OptoSigma class
            % 
            arguments
                portname char
                NameValueArgs.controllerName string = "General"
                NameValueArgs.maxAxes double {mustBeInterger, mustBePositive}
                NameValueArgs.baudrates double {mustBeInterger, mustBePositive}
                NameValueArgs.stageNames string = ["General"];
                NameValueArgs.axes double {mustBeInterger}
                NameValueArgs.divides double {mustBeInteger}
                NameValueArgs.mmperpulse double 
                NameValueArgs.debugmode (1,1) logical = false;
            end
            getField = @(field,default)feval(@(list,index)list{index},{default,@()NameValueArgs.(field)},uint8(isfield(NameValueArgs, field)+1));
                      % getField(filedname, defaultvalue): Returns field value of NameValueArgs. if there is no filed, return defalut value. 
            inst.flgDebug = NameValueArgs.debugmode;


            portList = MID_OptoSigma.GetSerialPortByName(portname);
            if(numel(portList)==0)
                portname = input('Input port number (ex.''COM13''):');
            else
                portname = portList{1};% 同じものが二つ以上のアダプタでマッチしてしまったら，最初に見つかったものを選ぶ．
            end
            
            inst.controllerName = NameValueArgs.controllerName;
            switch(lower( inst.controllerName ))
                case {'shot-702', 'shot-702h'}
                    inst.maxAxes = getField("maxAxes", 2);
                    baudrate_candidates = getField("baudrates", 38400);
                case 'gip-101b'
                    inst.maxAxes = getField("maxAxes", 1);
                    baudrate_candidates = getField("baudrates", [9600,38400,57600]);
                case 'general'
                    inst.maxAxes = getField("maxAxes", inf);
                    if(isfield(NameValueArgs, "baudrates"))
                        baudrate_candidates = NameValueArgs.baudrates;
                    else
                        error("Specify baudrate by using option 'baudrate', or specify controller supported by this program.")
                    end
                otherwise
                    error('Controller "%s" is not supported.\n', NameValueArgs.controllerName);
            end
            % find working baudrate from baudrate_candidates
            baudrate = nan;
            for idx=1:numel(baudrate_candidates)
                inst.serialObj = serialport(portname, baudrate_candidates(idx), 'Parity', 'none', 'DataBits', 8, 'StopBits', 1, 'FlowControl', 'hardware');
                configureTerminator(inst.serialObj, "CR/LF");
                inst.clearBuffer();
                writeline( inst.serialObj, "?:V" );
                versionstr = read(inst.serialObj, 5, "char");
                pat = "V" + digitsPattern() + "." + digitsPattern();
                if(matches(versionstr, pat))
                    baudrate = baudrate_candidates(idx);
                    break;
                end
                inst.clearBuffer();
                clear inst.serialObj;
            end
            if(isnan(baudrate))
                error('MID_OptoSigma::Working baudrate not exists in the list.');
            end
            fprintf('Controller %s on port %s was successifully opened\n', inst.controllerName, portname);

            % set number of available axes
            if(isfield(NameValueArgs,"axes"))
                inst.axes = NameValueArgs.axes;
                if(isfield(NameValueArgs,"stageNames"))
                    assert(numel(NameValueArgs.stageNames)==NameValueArgs.axes,...
                        "The number of 'StageNames' and 'axes' is different.\n" + ...
                        "Note that option 'axes' is the number of available axis.");
                end
            else
                inst.axes = numel(NameValueArgs.stageNames);
            end

            % add stage names
            stageNames = NameValueArgs.stageNames;
            if(numel(stageNames) < inst.axes)
                for idx = numel(stageNames)+1:inst.axes
                    stageNames(idx) = "General";
                end
            end

            % set divides
            switch(lower(inst.controllerName))
                case {'shot-702', 'shot-702h'}
                    inst.divides(1) = round(str2double(inst.sendMessage('?:S1')));
                    inst.divides(2) = round(str2double(inst.sendMessage('?:S2')));
                    if(isfield(NameValueArgs,"divides"))
                        warining(...
                            "MID_OptoSigma:: On SHOT-702 or SHOT-702H the value of divides can be read via RS232C.\n" + ...
                            "                The specified value %d is ignored.", NameValueArgs.divides(1));
                    end
                case 'gip-101b'
                    if(isfield(NameValueArgs,"divides"))
                        inst.divides(1) = NameValueArgs.divides(1);
                    else
                        warning(...
                            "MID_OptoSigma:: The divides (or steps) of pulse is determined by hardware setting on GIP-101B.\n" + ...
                            "                As the program cannot read the divides of pulse, you should specify the value.\n" + ...
                            "                Assume divides of 20. If this value differs from the hardware-set value, the stage may move to an unspected position.");
                        inst.divides(1) = 20;
                    end
                otherwise
                    if(isfield(NameValueArgs,"divides"))
                        inst.divides(1) = NameValueArgs.divides(1);
                    else
                        error(...
                            "Specify number of divides by using option 'divides', or specify controller supported by this program.");
                    end
            end

            % set pitch of the axes
            if(isfield(NameValueArgs,"mmperpulse"))
                inst.mmperfullpulse = NameValueArgs.mmperpulse;
            else
                for idxStage = inst.axes
                    switch(lower(NameValueArgs.stageNames(idxStage)))
                        case {'osms26-200(z)','osms20-85(x)'}
                            inst.mmperfullpulse(idxStage) = 4e-3;
                        case {'osms26-200(z)-g10'} % Special versions with geared motor
                            inst.mmperfullpulse(idxStage) = 4e-4;
                        case 'hps60-20x-m5'
                            inst.mmperfullpulse(idxStage) = 2e-3;
                        otherwise
                            warining(...
                                "Stage '%s' is not supported. The pitch of the axes is assume to 1um/pulse.\n" + ...
                                "Specify the pitch by using option 'mmperpulse', or specify stage supported by this program.", NameValueArgs.stageNames(idxStage));
                    end
                end
            end
            % output the setting
            spaces = "   ";
            fprintf(...
                "MID_OptoSimga:: Setting completed.\n" + ...
                spaces+"Controller: %s\n"+...
                spaces+"            port:%s\n"+ ...
                spaces+"            baudrate:%dbps\n", ...
                inst.controllerName,  portname, baudrate);
            for idx = 1:inst.axes
                fprintf(...
                    spaces+"Axis %d: %s\n" + ...
                    spaces+"        divides: %d\n"+...
                    spaces+"        full step: %fum/fullpulse\n" + ...
                    spaces+"        microstep: %fum/realpulse\n",...
                    idx, stageNames(idx), inst.divides(idx), ...
                    inst.mmperfullpulse(idx)*1e3, inst.mmperfullpulse(idx)*1e3/inst.divides(idx));
            end
        end
        
        function waitForSend( inst )
            %CTSが１であることを確認．Matlab R2019以上で使用可能，
            % 加えて，！コマンドでの応答がRになっていることを確認
            if(inst.flgDebug)
                fprintf('waitForSend:');
            end
            while( true ) 
                status = getpinstatus(inst.serialObj);
                if(status.ClearToSend == 1)
                    answer = inst.sendMessage('!:', true);
                    if(answer == 'R')
                        break;
                    else
                        if(inst.flgDebug)
                            fprintf('m');
                        end
                    end
                else
                    if(inst.flgDebug)
                        fprintf('c');
                    end
                end
                pause(0.1);
            end
            if(inst.flgDebug)
                fprintf('done\n');
            end
        end
        function clearBuffer( inst )
            %シリアルの受信バッファをクリア
            flush( inst.serialObj );
            %コマンド送信前にバッファ内のデータがあれば読み捨てる．
            while(inst.serialObj.NumBytesAvailable > 0)
                readline( inst.serialObj ); %バッファ内のデータがあれば読み捨てる．
            end
        end
        function [answer] = sendMessage( inst, message, flgQuiet)
            arguments
                inst
                message char
                flgQuiet (1,1) logical = false;
            end
            try
                inst.clearBuffer();
                writeline( inst.serialObj, message );
                answer = readline( inst.serialObj ); % 全てのコマンドに対してcall backが必ずある. queryならもちろんある．
                while(inst.serialObj.NumBytesAvailable > 0)
                    answer = join([answer, readline( inst.serialObj )]);
%                     pause(0.01); %バッファに残りがないかをチェックする前に少し待つ．
                end
            catch exception
                fprintf('MID_OptoSigma:sendMessage Error detected.\n' );
                fprintf('pinstatus:\n')
                getpinstatus(inst.serialObj)
                rethrow(exception)
            end
            if( inst.flgDebug && ~flgQuiet) 
                fprintf('sendMessage():sent \"%s\"\n', message );
                fprintf('sendMessage():answer is \"%s\"\n', answer);
            end
        end
        
        function driveAbs(inst, axes, vals, NameValueArgs)
            arguments
                inst
                axes double {mustBeInteger(axes), mustBeGreaterThanOrEqual(axes,1), mustBeLessThanOrEqual(axes,2)} 
                vals double
                NameValueArgs.acc = 10; % accereration(mm/s^2)
                NameValueArgs.unit char = 'mm'
            end
            for idx = numel(axes)
                axis = axes(idx);
                val = vals(idx);
                switch(lower(NameValueArgs.unit))
                    case 'mm'
                        coef = inst.divides(axis)/inst.mmperfullpulse(axis);
                    case 'pulse'
                        coef = 1.0;
                end
                pulse = round(val*coef);
                if( pulse >= 0 )
                    sign = '+';
                else
                    sign = '-';
                    pulse = -pulse;
                end
                
                Spulse = floor( inst.m_strt_mmps/inst.mmperfullpulse(axis)*inst.divides(axis));
                Fpulse = floor( min( ...
                    min(inst.m_max_mmps, inst.e_maxR_ms/1000*NameValueArgs.acc+inst.m_strt_mmps)/inst.mmperfullpulse(axis)*inst.divides(axis),...
                    inst.e_max_pps));
                Rtime = min(inst.e_maxR_ms, ceil((inst.m_max_mmps-inst.m_strt_mmps)/min(NameValueArgs.acc, inst.m_max_mmps2)*1000));
                mustBePositive(Spulse);
                mustBePositive(Fpulse);
                mustBePositive(Rtime);
                if(inst.flgDebug)
                    fprintf('To set speed S%dF%dR%d\n',Spulse,Fpulse,Rtime)
                end
                inst.waitForSend();
                prevSpeed(idx) = string(inst.sendMessage(sprintf('?:D%d',axis)));
                if(inst.flgDebug)
                    fprintf('Current speed is %s\n', prevSpeed);
                end
                inst.waitForSend();
                inst.sendMessage(sprintf('D:%dS%dF%dR%d',axis,Spulse,Fpulse,Rtime));
                inst.waitForSend();
                currSpeed = inst.sendMessage(sprintf('?:D%d',axis));
                if(inst.flgDebug)
                    fprintf('Current speed is %s\n', currSpeed);
                end
                inst.waitForSend();
                inst.sendMessage(sprintf('A:%d%cP%d', axis, sign, pulse));
            end
            inst.sendMessage(sprintf('G:'));
            for idx = numel(axes)
                axis = axes(idx);
                inst.waitForSend();
                inst.sendMessage(sprintf('D:%d%s',axis,prevSpeed(idx)));
                inst.waitForSend();
                currSpeed = inst.sendMessage(sprintf('?:D%d',axis));
                if(inst.flgDebug)
                    fprintf('Current speed is %s\n', currSpeed);
                end
            end
        end
        
        function delete(inst)
            delete(inst.serialObj);
            fprintf('OptoSigma stage %s was successifully closed\n', inst.controllerName);
        end
    end
    methods(Static)
        function [ portList ] = GetSerialPortByName( name )
            %getSerialPortByName
            % PnP Entity Name(デバイスマネージャでみられる名前）あるいはデバイス
            % インスタンスパスと一致するポート番号(COM1~COM256)のリストを返す。
            %   PnP Entity Nameはデバイスマネージャでリストにされる名前
            %    ex. Prolific USB-to-Serical Comm Port (COM7)
            %   *+与えられた名前+*+(COM*)の形になっているものをチェックする．
            %   デバイスインスタンスパスはデバイスマネージャでプロパティを開いたあと，
            %   詳細タブのプロパティ(P)の「デバイスインスタンスパス」で得られる値．
            %   ちゃんと確認していないが，多分その部品ごとに固有
            %    ex. USB\VID_067B&PID_2303\5&2ED43146&0&3
            %
            %   .NETの機能を使う上、Windowに強く依存した場所を読みに行くので、Windowsじゃないとほとんど動く見込みなし。
            %   name: 検索したいポートのPnP Entity nameか，デバイスインスタンスパスを与える。PnP Entitiy nameには正規表現が使える。
            %   portList: 検索に引っかかったポート番号をn行1列のセル配列に入れて返す。
            arguments (Input)
                name char
            end
            arguments(Output)
                portList char
            end
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
                    pnpentityname = char(manageObject.GetPropertyValue('Name'));
                    pnpdeviceid = char(manageObject.GetPropertyValue('PNPDeviceID'));
                    if(~isempty( regexp( pnpentityname,'\(COM[1-9][0-9]?[0-9]?\)','ONCE') ) && ...
                       ~isempty( regexp( pnpentityname, name, 'ONCE')) || ...
                       contains( pnpdeviceid, name,"IgnoreCase",true ))
                        matchStr = regexp( pnpentityname, '\(COM[1-9][0-9]?[0-9]?\)', 'match');
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