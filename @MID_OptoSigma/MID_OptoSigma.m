classdef MID_OptoSigma < handle
    %Class for OptoSigma stage controller
    % History:
    % 2024/9/6 Written by N.Matsuda.

    properties
        serialObj;
        flgDebug;
        controllerName;
        maxAxes;         % Maximum number of axes a controller can handle
        mmperfullpulse;  % Stage travel per pulse (full pulse) when division is assumed to be 1. unit mm. Depends on stage part number.
        divides;         % Steps per fullpulse
        axes;            % Number of axes used (axes<=maxAxes)
        baudrate;
        e_max_pps;       % electrical maximum velocity. The value is determined by controller (pulse/s)
        e_maxR_ms;       % electrical maximum of rising time (ms)
        m_strt_mmps = 0.4;  % starting velocity (mm/s)
        m_max_mmps2 = 180; % maximum acceleration (mm/s^2)
        m_max_mmps;        % maximum velocity (mm/s); Depends on stage part number
        version = 0.2;

    end
    
    methods
        function inst = MID_OptoSigma(portname, NameValueArgs)
            %MID_OPTOSIGMA 
            %   constructor of MID_OptoSigma class
            % 
            arguments (Input)
                portname string
                NameValueArgs.controllerName string = "General"
                NameValueArgs.maxAxes (1,1) double {mustBeInterger, mustBePositive}
                NameValueArgs.baudrates double {mustBeInterger, mustBePositive}
                NameValueArgs.stageNames string = ["General"];
                NameValueArgs.axes (1,1) double {mustBeInterger, mustBePositive}
                NameValueArgs.divides double {mustBeInteger, mustBePositive}
                NameValueArgs.mmperpulse double {mustBePositive}
                NameValueArgs.debugmode (1,1) logical = false;
            end
            arguments (Output)
                inst (1,1) MID_OptoSigma
            end
            getField = @(field,default)feval(@(list,index)list{index},{default,@()NameValueArgs.(field)},uint8(isfield(NameValueArgs, field)+1));
                      % getField(filedname, defaultvalue): Returns field value of NameValueArgs. if there is no filed, return defalut value. 
            inst.flgDebug = NameValueArgs.debugmode;
            
            while(1)
                if(numel(portname) == 1 && matches(portname,"COM"+digitsPattern()))
                    decidedPortName = portname{1};
                    break;
                end
                if(numel(portname) == 1)
                    portname = MID_OptoSigma.GetSerialPortByName(portname);
                    if(numel(portname) == 1)
                        continue;
                    end
                elseif(numel(portList)==0)
                    portname = input('Input port number (ex.''COM13''):');
                end
                if(numel(portname)>1)
                    fprintf('Port list has multple candidates.\n')
                    for idxPort = 1:numel(portname)
                        fprintf('   %s\n', portname(idxPort));
                    end
                    portname = input('Input port number (ex.''COM13''):');
                end
            end
            
            inst.controllerName = NameValueArgs.controllerName;
            switch(lower( inst.controllerName ))
                case {'shot-702', 'shot-702h'}
                    inst.maxAxes = getField("maxAxes", 2);
                    baudrate_candidates = getField("baudrates", 38400);
                    inst.e_max_pps = 500e3;  % electrical maximum velocity (pulse/s)
                    inst.e_maxR_ms = 1000;   % electrical maximum of rising time (ms)
                case 'gip-101b'
                    inst.maxAxes = getField("maxAxes", 1);
                    baudrate_candidates = getField("baudrates", [9600,38400,57600]);
                    inst.e_max_pps = 500e3;  % electrical maximum velocity (pulse/s)
                    inst.e_maxR_ms = 1000;   % electrical maximum of rising time (ms)
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
                inst.serialObj = serialport(decidedPortName, baudrate_candidates(idx), 'Parity', 'none', 'DataBits', 8, 'StopBits', 1, 'FlowControl', 'hardware');
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
                for idxStage = 1:inst.axes
                    switch(lower(NameValueArgs.stageNames(idxStage)))
                        case 'osms26-200(z)'
                            inst.mmperfullpulse(idxStage) = 4e-3;  %Stage travel per full pulse (mm/pulse);
                            inst.m_max_mmps(idxStage) = 10.0;      % maximum velocity (mm/s);
                        case {'osms26-200(z)-g10'} % Special versions with geared motor
                            inst.mmperfullpulse(idxStage) = 4e-4;  %Stage travel per full pulse (mm/pulse);
                            inst.m_max_mmps(idxStage) = 1.0;       % maximum velocity (mm/s);
                        case 'osms20-85(x)'
                            inst.mmperfullpulse(idxStage) = 2e-3;  %Stage travel per full pulse (mm/pulse);
                            inst.m_max_mmps(idxStage) = 25.0;      % maximum velocity (mm/s);
                        case 'hps60-20x-m5'
                            inst.mmperfullpulse(idxStage) = 2e-3;  %Stage travel per full pulse (mm/pulse);
                            inst.m_max_mmps(idxStage) = 10.0;      % maximum velocity (mm/s);
                        otherwise
                            warning(...
                                "Stage '%s' is not supported. The pitch of the axes is assume to 1um/pulse.\n" + ...
                                "Specify the pitch by using option 'mmperpulse', or specify stage supported by this program.", NameValueArgs.stageNames(idxStage));
                            inst.mmperfullpulse(idxStage) = 1e-3;
                    end
                end
            end
            % output the setting
            spaces = "   ";
            fprintf(...
                "MID_OptoSimga:: Setting completed.\n" + ...
                spaces+"Controller: %s\n"+...
                spaces+"            port:%s\n"+ ...
                spaces+"            baudrate:%dbps\n"+ ...
                spaces+"            available axis:%d\n", ...
                inst.controllerName,  portname, baudrate, inst.axes);
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
        function delete(inst)
            delete(inst.serialObj);
            fprintf('OptoSigma stage %s was successifully closed\n', inst.controllerName);
        end

        function driveAbs(inst, axes, vals, NameValueArgs)
            % 指定の軸（複数指定可能）を指定の値に動かす．
            % 移動が終わるまで，ブロッキングする関数
            arguments(Input)
                inst (1,1) MID_OptoSigma
                axes (1,:) double {mustBeInteger, mustBePositive} 
                vals (1,:) double {mustBeReal}
                NameValueArgs.acc = 10; % accereration(mm/s^2)
                NameValueArgs.unit string {mustBeMember(NameValueArgs.unit, ["mm","pulse"])} = "mm" 
            end
            assert(all(axes<=inst.axes),"Argument 'axes' must be smaller than available axes.")
            assert(numel(axes)==numel(vals));
            prevSpeed = zeros(3,numel(axes));
            specifiedPulse = zeros(1,numel(axes));
            for idx = 1:numel(axes)
                axis = axes(idx);
                val = vals(idx);
                switch(lower(NameValueArgs.unit))
                    case 'mm'
                        pulse = inst.mm2pulse(axis, val);
                    case 'pulse'
                        pulse = val;
                end
                specifiedPulse(idx) = pulse;
            end
            % speed setting
            for idx = 1:numel(axes)
                axis = axes(idx);
                Spulse = floor( inst.mm2pulse(axis, inst.m_strt_mmps));
                Fpulse = floor( inst.mm2pulse(axis, (inst.e_maxR_ms/1000*NameValueArgs.acc+inst.m_strt_mmps)));
                Rtime = min(inst.e_maxR_ms, ceil((inst.m_max_mmps(axis)-inst.m_strt_mmps)/min(NameValueArgs.acc, inst.m_max_mmps2)*1000));
                prevSpeed(:,idx) = inst.querySpeed(axis);
                inst.setSpeed(axis, [Spulse, Fpulse, Rtime]);
            end
            
            if(numel(axes)==2 && (all(axes == [1 2]) || all(axes == [2 1])))
                if(all( axes == [1 2]))
                    idx1 = 1; idx2 = 2;
                else
                    idx1 = 2; idx2 = 1;
                end
                [sign1, absPulse1] = inst.toSignAndAbsPulse(specifiedPulse(idx1));
                [sign2, absPulse2] = inst.toSignAndAbsPulse(specifiedPulse(idx2));
                inst.waitForSend();
                inst.sendMessage(sprintf('A:W%cP%d%cP%d', sign1, absPulse1, sign2, absPulse2));
                inst.sendMessage(sprintf('G:'));
            else
                for idx = 1:numel(axes)
                    axis = axes(idx);
                    [sign, absPulse] = inst.toSignAndAbsPulse(specifiedPulse(idx));
                    inst.waitForSend();
                    inst.sendMessage(sprintf('A:%d%cP%d', axis, sign, absPulse));
                    inst.sendMessage(sprintf('G:'));
                end
            end
            %軸が止まるまで停止
            inst.waitForSend();

            posInPulse = inst.queryAllPosition();
            for idx = 1:numel(axes)
                axis = axes(idx);
                inst.setSpeed(axis, prevSpeed(:,idx));
                if(posInPulse(axis) ~= specifiedPulse(idx))
                    warning("Axis %d has not moved to the specified position\n(%dpulse(%fmm)/now %dpulse(%fmm)).", ...
                        axis, ...
                        specifiedPulse(idx), inst.pulse2mm(axis,specifiedPulse(idx)), ...
                        posInPulse(axis), inst.pulse2mm(axis,posInPulse(axis)) );
                end
            end
        end

        function wait(inst)
            %軸がすべて止まるまでMatlabの処理を止める関数
            inst.waitForSend();
        end

        function [addr] = queryAddress(inst, axes, NameValueArgs)
            arguments(Input)
                inst  (1,1) MID_OptoSigma
                axes (1,:) double {mustBeInteger, mustBePositive} = 1:inst.axes
                NameValueArgs.unit string {mustBeMember(NameValueArgs.unit, ["mm","pulse"])} = "mm" 
            end
            arguments(Output)
                addr (1,:) double
            end
            addrInPulse = inst.queryAllPosition();
            switch(lower(NameValueArgs.unit))
                case 'mm'
                    addr = zeros(1,numel(axes));
                    for idx = 1:numel(axes)
                        axis = axes(idx);
                        addr(idx) = inst.pulse2mm(axis, addrInPulse(axis));
                    end
                case 'pulse'
                    addr = addrInPulse(axes);
            end
            if(inst.flgDebug)
                fprintf("Current position:\n");
                for idxAxis = 1:inst.axes
                    fprintf("  axis %d: %d pulse (%fmm)\n", idxAxis, addrInPulse(idxAxis), inst.pulse2mm(idxAxis, addrInPulse(idxAxis)));
                end
            end
        end

        %%これより下，内部関数
        function [sign,absPulse] = toSignAndAbsPulse(inst, pulse)
            if( pulse >= 0 )
                sign = '+';
                absPulse = pulse;
            else
                sign = '-';
                absPulse = -pulse;
            end
        end
        function mm = pulse2mm(inst, axis, pulse)
            arguments(Input)
                inst (1,1) MID_OptoSigma
                axis (1,1) double {mustBePositive, mustBeInteger}
                pulse double {mustBeReal}
            end
            arguments(Output)
                mm double
            end
            assert(axis<=inst.axes,"Argument 'axis' must be smaller than available axes.")
            mm = pulse*inst.mmperfullpulse(axis)/inst.divides(axis);
        end
        function pulse = mm2pulse(inst, axis, mm)
            arguments(Input)
                inst (1,1) MID_OptoSigma
                axis (1,1) double {mustBePositive, mustBeInteger}
                mm double {mustBeReal}
            end
            arguments(Output)
                pulse double
            end
            assert(axis<=inst.axes,"Argument 'axis' must be smaller than available axes.")
            pulse = mm/inst.mmperfullpulse(axis)*inst.divides(axis);
        end
        function [posInPulse] = queryAllPosition(inst)
            arguments(Input)
                inst  (1,1) MID_OptoSigma
            end
            arguments(Output)
                posInPulse (1,:) double {mustBeInteger}
            end
            % QコマンドはBusy状態でも発行できる
            posStr = inst.sendMessage("Q:");
            numPat = optionalPattern("-")+asManyOfPattern(" ")+digitsPattern()+",";
            posStrPat = asManyOfPattern(numPat)+("X"|"K")+","+("L"|"M"|"W"|"K"|"R")+","+("B"|"R");
            assert(matches(posStr, posStrPat), "Return string %s does not match the pattern.", posStr);
            numStr = extract(posStr, numPat);
            ackStr = extract(posStr, ("X"|"K")+","+("L"|"M"|"W"|"K"|"R")+","+("B"|"R"));
            ackStrSplit = split(ackStr, ",");
            assert(ackStrSplit(1) == "K", "Q command error");
            switch(ackStrSplit(2))
                case "L"
                    warning("Axis 1 stops for limit sensor.");
                case "M"
                    warning("Axis 2 stops for limit sensor.");
                case "W"
                    if(inst.maxAxes == 4)
                        warning("All axes (1~4) stop for limit sensor.");
                    else
                        warning("Axes 1 and 2 stop for limit sensor.");
                    end
            end
            sign = matches(numStr, "-"+asManyOfPattern(" ")+digitsPattern()+",");
            sign = sign*-2+1;
            val = str2double(extract(numStr, digitsPattern()));
            posInPulse = (sign.*val).';
        end
        function spd = setSpeed(inst, axis, spd_toset)
            arguments
                inst (1,1) MID_OptoSigma
                axis (1,1) double {mustBePositive, mustBeInteger}
                spd_toset (1,3) double {mustBePositive, mustBeInteger}
            end
            assert(axis<=inst.axes,"Argument 'axis' must be smaller than available axes.")
            spd_toset(1) = min([spd_toset(1), inst.mm2pulse(axis, inst.m_strt_mmps)]);
            spd_toset(2) = max( [min([spd_toset(2), inst.e_max_pps, inst.mm2pulse(axis, inst.m_max_mmps(axis))]), spd_toset(1)]); % Fastest speed (pulse/s)
            spd_toset(3) = min( [spd_toset(3), inst.e_maxR_ms]); %Rising time (ms)
            inst.debugPrint(...
                "setSpeed:: axis = %d\n" + ...
                "           Start speed   = %d pulse/s (%f mm/s)\n" + ...
                "           Fastest speed = %d pulse/s (%f mm/s)\n" + ...
                "           Rising time   = %d ms\n"  ...
                , axis, ...
                spd_toset(1), inst.pulse2mm(axis, spd_toset(1)),...
                spd_toset(2), inst.pulse2mm(axis, spd_toset(2)),...
                spd_toset(3));

            inst.waitForSend();
            inst.sendMessage(sprintf('D:%dS%dF%dR%d',axis,spd_toset(1),spd_toset(2),spd_toset(3)));
            inst.waitForSend();
            spd = inst.querySpeed(axis);
            if( ~all(spd == spd_toset))
                warning("Speed cannot set (S,F,R)=(%d,%d,%d)\nbut set to (%d,%d,%d)\n",spd_toset(1),spd_toset(2),spd_toset(3), spd(1), spd(2), spd(3));
            end
        end
        function spd = querySpeed(inst, axis)
            arguments(Input)
                inst (1,1) MID_OptoSigma
                axis (1,1) double {mustBePositive, mustBeInteger}
            end
            arguments(Output)
                spd (1,3) double {mustBeReal}
            end
            inst.waitForSend();
            speedStr = string(inst.sendMessage(sprintf('?:D%d',axis)));
            assert(matches(speedStr,"S"+digitsPattern()+"F"+digitsPattern()+"R"+digitsPattern()));
            S = str2double(extractBetween(speedStr,"S","F"));
            F = str2double(extractBetween(speedStr,"F","R"));
            R = str2double(extractAfter(speedStr,"R"));
            mustBePositive([S,F,R]);
            spd = [S, F, R];
        end
        function waitForSend( inst )
            arguments(Input)
                inst (1,1) MID_OptoSigma
            end
            %CTSが１であることを確認．Matlab R2019以上で使用可能，
            % 加えて，！コマンドでの応答がRになっていることを確認
            inst.debugPrint('waitForSend:');
            while( true ) 
                status = getpinstatus(inst.serialObj);
                if(status.ClearToSend == 1)
                    answer = inst.sendMessage('!:', true);
                    if(answer == 'R')
                        break;
                    end
                    inst.debugPrint('m');
                else
                    inst.debugPrint('c');
                end
                pause(0.1);
            end
            inst.debugPrint('done\n');
        end
        function clearBuffer( inst )
            arguments(Input)
                inst (1,1) MID_OptoSigma
            end
            %シリアルの受信バッファをクリア
            flush( inst.serialObj );
            %コマンド送信前にバッファ内のデータがあれば読み捨てる．
            while(inst.serialObj.NumBytesAvailable > 0)
                readline( inst.serialObj ); %バッファ内のデータがあれば読み捨てる．
            end
        end
        function [answer] = sendMessage( inst, message, flgQuiet)
            arguments(Input)
                inst (1,1) MID_OptoSigma
                message char
                flgQuiet (1,1) logical = false;
            end
            arguments(Output)
                answer (1,1) string
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
        function debugPrint(inst, format, vars)
            arguments(Input)
                inst (1,1) MID_OptoSigma
                format (1,1) string
            end
            arguments(Repeating)
                vars
            end
            if(inst.flgDebug)
                fprintf(format, vars{:});
            end
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
                name (1,1) string
            end
            arguments(Output)
                portList (1,:) string
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