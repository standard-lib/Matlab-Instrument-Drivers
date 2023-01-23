classdef MID_CV87x < handle
    % Scanner class
    %   obj = MID_CV87x()でインスタンスを定義
    %   例：
    %       PS = MID_CV87x();--------------------オブジェクトPSを作成
    %       PS.resetAddress('Y');----------------アドレスをリセット
    %       PS.setSpeed('Y', 'fast');---Y軸のS字ドライブ速度を'fast'に設定
    %       PS.driveAbs('Y', 30, 'Z', 20);------------Y軸のS字ドライブ(+30mm)を実行
    % 変更したいこと一覧(2018松田）
    % ・可動域制限とか速度制限とかはscanner.confからデフォルトで読み込みたい．
    % ・Boardnumはボードの数だけ用意されるべきで，０を仮定したくない．
    % ・Drive速度などをscanner.confを読み込んで決めさせたい．軸の名前はscanner.confで決めたい
    % ・軸の名前を strfind('XYZRA',
    % upper(num))で軸番号に変換しているが，
    % ・プログラム中に可能な限りリテラルの数字を書かない．おそらくscanner.confから読み取れる値のはず．
    % ・ジョグモードを追加したい．PS.jog()を実行すると，Escを押すまで，キー待ちをして，
    % F1:第1軸＋，F2:第1軸－，F3：第2軸＋．．．のようなジョグを行う．ショートカットキーはInsight Scanに準拠する．
    properties(SetAccess = private)
        hDev;       % デバイス変数(32ビット符号なし整数DWORD)
        boardNo;
        axisNo;
        enable;
        label;
        unit;
        pulseResolution;
        pulseReverse;     % 軸を反転するか
        
        Degmm2Pulse % 1Degree or 1mm が何パルスに対応するか
        Vel_Max;    %速度域制限:   あやまって大きく動かしすぎないように保険を掛ける
        Accel_Max;  %加速度域制限: あやまって大きく動かしすぎないように保険を掛ける
        Vel_3level; %低中高 速度値: 低速と中速と高速の速度値を格納
        Ini_Ldrive_data; %L driveの初期設定値
        Ini_Sdrive_data; %S driveの初期設定値
        Axis_num;   %軸の番号リスト
        Axis_char;
        %ここのﾊﾟﾗﾒｰﾀは自分で適宜決める
    end    
    properties( Constant )
%         Boardnum = uint16(0); % 2014/7/26現在Board numberは0だけ
    end
   
    methods
        %////// コンストラクタ //////
        function obj = MID_CV87x()
            if (~libisloaded('Mc06A'))
                loadlibrary('Mc06A','Mc06A.h');
            end
            M = readcell('scanner.conf', 'FileType', 'text');
            cols = 2:size(M,2);
            obj.boardNo = uint16(cell2mat(pickRow(M, 'BoardNo', cols)));
            obj.axisNo  = uint32(cell2mat(pickRow(M, 'AxisNo', cols)));
            obj.enable  = strcmpi('true', pickRow(M, 'Enable', cols));
            obj.label   =                 pickRow(M, 'Label', cols);
            obj.unit    =                 pickRow(M, 'Unit', cols);
            obj.pulseResolution = cell2mat(pickRow(M, 'PulseResolution', cols));
            obj.pulseReverse = strcmpi('true', pickRow(M, 'PulseReverse', cols));
            
            obj.Axis_num = uint32([0 1 2 3]);
            obj.Axis_char = 'XYZR';
            
            obj.Degmm2Pulse = [1000, 1000, 5000, 100000/360];  %[Pulse/mm, Pulse/mm, Pulse/mm, Pulse/deg, Pulse/deg]
                                                                             %X,Y: 500*40/10,  基本ステップ角:500Pulse/Rev, 分割設定:1/40,  ねじピッチ:10mm
                                                                             %Z  : 200*100/2,  基本ステップ角:200Pulse/Rev, 分割設定:1/100, ねじピッチ:2mm
                                                                             %R,A: 500*200/360,基本ステップ角:500Pulse/Rev, 分割設定:1/200
%             obj.Move_Limit = [ 713,  468, 310, 180];          %[mm, mm, mm, deg]
            obj.Vel_Max    = [ 750,  200,  10,  50];            %[mm/s, mm/s, mm/s, deg/s, deg/s]
            obj.Accel_Max  = [5000, 1000, 200, 0.2];      %[mm/s^2, mm/s^2, mm/s^2, deg/s^2, deg/s^2]
            obj.Vel_3level = [   5,  40,  80; ...
                                 5,  20,  50; ...
                                 1,  5,  10; ... %[ 'slow','medium','fast' ]それぞれの速度
                                10, 20,   40];  
            obj.Ini_Ldrive_data = [0.1, 5,   5,   5; ... %Ldrive初期設定値 [開始&終了速度(mm/s),最大速度(mm/s),立上り加速度(mm/s^2),立下り加速度(mm/s^2)] 
                                   0.1, 5,   5,   5; ... %  〃
                                   0.1, 1,   5,   5; ... %  〃
                                   0.01, 1, 0.1, 0.1];    %Ldrive初期設定値 [開始&終了速度(deg/s),最大速度(deg/s),立上り加速度(deg/s^2),立下り加速度(deg/s^2)] 
            obj.Ini_Sdrive_data = [0.1, 5,   5,   5,   2,   2,   2,   2; ... %Sdrive初期設定値 [開始&終了速度(mm/s),最大速度(mm/s),立上り加速度(mm/s^2),立下り加速度(mm/s^2), S字部速度1~4(mm/s)] 
                                   0.1, 5,   5,   5,   2,   2,   2,   2; ... %  〃
                                   0.1, 1,   5,   5, 0.4, 0.4, 0.4, 0.4; ... %  〃
                                   0.01, 1, 0.1, 0.1, 0.2, 0.2, 0.2, 0.2];     %Sdrive初期設定値 [開始&終了速度(deg/s),最大速度(deg/s),立上り加速度(deg/s^2),立下り加速度(deg/s^2), S字部速度1~4(deg/s)] 

            obj.BOpen(); %デバイスオープン            
            fprintf('All devices were successfully opened\n');
            obj.SetDriveSpeed('L', 'X', 'slow'); %すべての drive speed を'slow'に初期化
            obj.SetDriveSpeed('L', 'Y', 'slow');
            obj.SetDriveSpeed('L', 'Z', 'slow');            
            obj.SetDriveSpeed('L', 'R', 'slow');
            obj.SetDriveSpeed('S', 'X', 'slow');
            obj.SetDriveSpeed('S', 'Y', 'slow');
            obj.SetDriveSpeed('S', 'Z', 'slow');
            obj.SetDriveSpeed('S', 'R', 'slow');
            
            % 第4軸は北條研の装置では，ストッパの論理がデフォルトとは逆なので，必ず直させる．
            devNum = 4;
            dataarr = zeros(1,3, 'uint16');
            dataarr(3) = uint16(0xFFF3); %set CWLM and CCWLM to negative logic inputs
            obj.writeMC06( devNum, 'drive', obj.HARD_INITIALIZE7, dataarr, 3);
        end
        
        %////// 処理関数 //////
        
        function driveAbs(obj, varargin )
            %DRIVEABS Drive axis with blocking.
            %
            % [] = obj.driveAbs( axis1, value1 [, axis2, value2...])
            % axisn : char
            %  Axis to move. Must be in 'X' or 'Y' or 'Z' or 'R'
            % value : numeric
            %  Destination value [mm] or [deg]
            p = inputParser;
            addParameter(p, 'X', [], @isnumeric);
            addParameter(p, 'Y', [], @isnumeric);
            addParameter(p, 'Z', [], @isnumeric);
            addParameter(p, 'R', [], @isnumeric);
            parse(p, varargin{:});
            celllist = {p.Results.X, p.Results.Y, p.Results.Z, p.Results.R};
            for idxAxis = 1:4
                destval = celllist{idxAxis};
                if(~isempty(destval))
                    obj.Drive(idxAxis,'absS', destval);
                end
            end
            for idxAxis = 1:4
                destval = celllist{idxAxis};
                if(~isempty(destval))
                    obj.Wait(idxAxis);
                end
            end
        end
        
        function resetAddress(obj, varargin )
            toresetaxis = concatinputstr(varargin);
            for axischar = toresetaxis
                num = int32(strfind(obj.Axis_char, upper(axischar)));
                assert( ~isempty(num), 'Invalid axis name `%c` is specified', axischar);
                %本当はdataarr = setdata1_24(設定したいカウント)ができる。
                obj.writeMC06( num, 'counter', obj.ADDRESS_COUNTER_PRESET, zeros(1,3, 'uint16'), [2 3]);
            end
        end
        
        function [addr] = queryAddress(obj)
            % ADDRESS COUNTER PORT SELECTコマンドを用いたアドレス読み出し
            % 取扱説明書（コマンド編）p89参照
            addr = zeros(1,4);
            for axis = 1:4
                dataarr = obj.readMC06( axis, obj.ADDRESS_COUNTER_PORT_SELECT);
                addr_int32 = getdata(dataarr, 'int32');
                addr(axis) = cast(addr_int32,"double") / obj.Degmm2Pulse(axis);
            end
        end
        
        function setSpeed(obj, speed, varargin )
            tosetaxis = concatinputstr(varargin);
            for axischar = tosetaxis
                obj.SetDriveSpeed('S', axischar, speed);
            end
        end
        
        function Wait(obj, num, varargin)
            %Wait(obj,num,Wait_time) waits until busy=0
            %   num: 1, 2, 3, 4, 5 or 'X', 'Y', 'Z', 'R', 'A' 
            %   Wait_time: maximum time to wait [ms]
            %   Wait time =0 or No argument ==> Wait infinitely
            if ischar(num), num = int32( strfind('XYZRA', upper(num)) ); end %numが文字列の場合 ==> 番号に変換
            if num<1 || num>5 || isempty(num)
                fprintf('Invalid argument. 1~5 or ''X'',''Y'',''Z'',''R'',''A'' is accepted.');
                return
            end

            result = struct('MC06_Result', zeros(1,4, 'uint16'));
            resultPtr = libpointer( 'MC06_TAG_S_RESULT', result );
            FUNC_NAME = 'MC06_BWaitDriveCommand';
            Wait_time = 0;
            if ~isempty(varargin), Wait_time = varargin{1}; end
            if Wait_time<0, Wait_time = 0; end

            [retVal, result] = calllib('Mc06A', FUNC_NAME, obj.hDev(num), uint16(Wait_time), resultPtr);
            obj.assertionMC06(retVal, result); % call error function
        end

        function stopScan(obj, devNum)
            %ScanStop(obj, num) stops the scan right now
            %   num: 1, 2, 3, 4, 5 or 'X', 'Y', 'Z', 'R', 'A' 
            if ischar(devNum), devNum = int32( strfind('XYZRA', upper(devNum)) ); end %numが文字列の場合 ==> 番号に変換
            if devNum<1 || devNum>5 || isempty(devNum)
                fprintf('Invalid argument. 1~5 or ''X'',''Y'',''Z'',''R'',''A'' is accepted.');
                return
            end
            result = struct('MC06_Result', zeros(1,4, 'uint16'));
            resultPtr = libpointer( 'MC06_TAG_S_RESULT', result );
            command = obj.FAST_STOP; % FAST STOP COMMAND 即時停止
            cmdPtr = libpointer('uint16Ptr', command);
            [retVal, ~, result] = calllib('Mc06A', 'MC06_BWDriveCommand', obj.hDev(devNum), cmdPtr, resultPtr);
            obj.assertionMC06(retVal, result); % call error function
        end

        %////// ScanDrive関連 (HEX CODE: 0020~0025, 0042~0045) //////
        function Drive(obj, Axisname, SCAN_TYPE, varargin)
            %Drive(obj, Axisname, SCAN_TYPE, varargin) excutes the drive
            %   Axisname  : 'X', 'Y', 'Z', 'R', or 'A'
            %   SCAN_TYPE : '+J'   :  +Jog Drive (one pulse)
            %               '-J'   :  -Jog Drive (one pulse)
            %               '+L'   :  + L_shape Drive (infinitely)
            %               '-L'   :  - L_shape Drive (infinitely)
            %               'incL' :  L_shape INC INDEX Drive
            %               'absL' :  L_shape ABS INDEX Drive
            %               '+S'   :  + S_shape Drive (infinitely)
            %               '-S'   :  - S_shape Drive (infinitely)
            %               'incS' :  S_shape INC INDEX Drive
            %               'absS' :  S_shape ABS INDEX Drive
            %   varvargin : movement( mm or deg )
            if(isnumeric(Axisname))
                num = Axisname;
            else
                num = int32( strfind('XYZRA', upper(Axisname)) ); %これでX,Y,Z,R,Aを1,2,3,4,5に対応付けできる
            end
            if isempty(num)
                error('Axisname has to be ''X'',''Y'',''Z'',''R'', or ''A''');
            end
            jogLikeKeys = {'+J', '-J', '+L', '-L', '+S', '-S'};
            jogLikeCommands = [obj.PLUSJOG, obj.MINUSJOG, obj.PLUSSCAN, obj.MINUSSCAN, obj.PLUS_SRATE_SCAN, obj.MINUS_SRATE_SCAN];
            incLikeKeys = {'incL', 'absL', 'incS', 'absS'};
            incLikeCommands = [obj.INC_INDEX, obj.ABS_INDEX, obj.INC_SRATE_INDEX, obj.ABS_SRATE_INDEX];
            switch SCAN_TYPE
                case jogLikeKeys
                    % +JOG, -JOG, +SCAN, -SCAN, +SRATE_SCAN, -SRATE_SCAN
                    command = jogLikeCommands( strcmp(jogLikeKeys, SCAN_TYPE) );
                    obj.writeMC06( num, 'drive', command, [], [] );
%                     obj.Wait(num, 0);
%                     obj.BWDriveCommand(num, dec2hex(command));
                case incLikeKeys
                    % INC_INDEX, ABS_INDEX, INC_SRATE_INDEX,
                    % ABS_SRATE_INDEX
                    Degmm = varargin{1};
                    pulse_num = int32( Degmm*obj.Degmm2Pulse(num) ); %Number of pulses
                    command = incLikeCommands( strcmp(incLikeKeys, SCAN_TYPE) );
                    dataarr = setdata1_32(pulse_num);
                    obj.writeMC06( num, 'drive', command, dataarr, [2 3]);
                otherwise
                    error('invalid SCANTYPE');
            end
        end
        
        %////// 設定関連(Drive parameters) //////
        function SetDrivePara(obj, LorS, Axisname, StartEnd_Vel, Max_Vel, Accel_1, Accel_2, varargin)
            %SetDrivePara(obj, LorS, Axisname, StartEnd_Vel, Max_Vel, Accel_1, Accel_2)
            %       or
            %SetDrivePara(obj, LorS, Axisname, StartEnd_Vel, Max_Vel, Accel_1, Accel_2, S_Vel1, S_Vel2, S_Vel3, S_Vel4)
            % sets the drive parameters
            %   LorS            : 'L' or 'S'
            %   Axisname        : 'X', 'Y', 'Z', 'R', or 'A'
            %   StartEnd_Vel    : Start & End Velocity [mm/s] or [deg/s]
            %   Max_Vel         : Maximum Velocity [mm/s] or [deg/s]
            %   Accel_1         : Start Acceleration [mm/s^2] or [deg/s^2]
            %   Accel_2         : End   Acceleration [mm/s^2] or [deg/s^2]
            %   S_Vel1~4        : S字部分の速度 [mm/s] or [deg/s] ('S'のときだけ)
            if nargin<7, error('Wrong number of input arguments') ; end

            num = int32( strfind('XYZRA', upper(Axisname)) ); %これでX,Y,Z,R,Aを1,2,3,4,5に対応付けできる
            if isempty(num)
                fprintf('Axisname has to be ''X'',''Y'',''Z'',''R'', or ''A''\n');
            else
                if strcmp(LorS, 'L')
                    obj. L_SetDrivePara(num, StartEnd_Vel, Max_Vel, Accel_1, Accel_2);
                elseif strcmp(LorS, 'S')
                    if nargin~=11, error('Wrong number of input arguments') ; end
                    obj.S_SetDrivePara(num, StartEnd_Vel, Max_Vel, Accel_1, Accel_2, S_Vel1, S_Vel2, S_Vel3, S_Vel4);
                else
                    fprintf('1st argument has to be ''L'' or ''S''\n');
                end
            end
        end

        %////// Drive speedを 低.中.高 の3段階で設定//////
        function SetDriveSpeed(obj, LorS, Axisname, Speed)
            %SetDriveSpeed(obj, LorS, Axisname, Speed) sets the Drive speed
            %   LorS     : 'L' or 'S'
            %   Axisname : 'X', 'Y', 'Z', 'R', or 'A'
            %   Speed    : 'slow', 'medium', or 'fast'
            assert( nargin==4, 'Wrong number of input arguments');
            num = int32( strfind('XYZRA', upper(Axisname)) ); %これでX,Y,Z,R,Aを1,2,3,4,5に対応付けできる
            assert( ~isempty(num), 'Axisname has to be ''X'',''Y'',''Z'',''R'', or ''A''');
            speed_text = {'slow', 'medium', 'fast'};
            speed_idx = find(strcmpi(speed_text, Speed));
            assert( ~isempty(speed_idx), '''Speed'' has to be ''slow'', ''medium'', or ''fast''');
            assert( any( strcmp(LorS, {'L', 'S'})), '1st argument has to be ''L'' or ''S''');
            if strcmp(LorS, 'L')
                obj.L_SetDrivePara(num, obj.Ini_Ldrive_data(num,1), obj.Vel_3level(num,speed_idx(1)), obj.Ini_Ldrive_data(num,3), obj.Ini_Ldrive_data(num,4));
            elseif strcmp(LorS, 'S')
                obj.S_SetDrivePara( num, obj.Ini_Sdrive_data(num,1), obj.Vel_3level(num,speed_idx(1)), obj.Ini_Sdrive_data(num,3), ...
                                        obj.Ini_Sdrive_data(num,4), obj.Ini_Sdrive_data(num,5), obj.Ini_Sdrive_data(num,6), ...
                                        obj.Ini_Sdrive_data(num,7), obj.Ini_Sdrive_data(num,8) );
            end
        end

        %////// DriveParameterの出力 //////
        function DriveParameter_output(obj, LorS, Axisname)
            %DriveParameter(obj, LorS, Axisname) outputs the current Drive Parameters
            %   LorS : 'L' or 'S'
            %   Axisname : 'X', 'Y', 'Z', 'R', or 'A'
            if nargin~=3, error('Wrong number of input arguments') ; end

            num = int32( strfind('XYZRA', upper(Axisname)) ); %これでX,Y,Z,R,Aを1,2,3,4,5に対応付けできる
            if isempty(num)
                fprintf('Axisname has to be ''X'',''Y'',''Z'',''R'', or ''A''\n');
            else
                if strcmp(LorS, 'L')
                    obj.LDriveParameter(num);
                elseif strcmp(LorS, 'S')
                    obj.SDriveParameter(num);
                else
                    fprintf('1st argument has to be ''L'' or ''S''\n');
                end
            end
        end

        %////// デストラクタ /////
        function delete(obj)
            %This is a Destructor: delete(obj)
            obj.BClose;
            clear obj
            fprintf('C_V872 stepping motor controller was successifully closed\n');
        end      
%    end %methods

%    methods( Access = private ) %外部からは参照することのない関数
        
        % signatures of methods in the private folder
        assertin(value, minimum, maximum)
        assertin_oc(value, minimum, maximum)
        [concatenatedstr] = concatinputstr(celllist)
        [value32] = getdata(arraydata, type)
        [valMSB, valLSB] = getdata_two8(arraydata, type)
        [arraydata] = setdata1_24(indata) %signature of setdata1_24
        [arraydata] = setdata1_32(int32data) %signature of setdata1_24
        [arraydata] = setdata_two8(indataMSB, indataLSB)

        function BOpen(obj)
            %Open(obj) opens a Device
            %   This function is automatically called by the Constructor, so
            %   you don't need to care about this function
            FUNC_NAME = 'MC06_BOpen';
%             result = struct('MC06_Result', zeros(1,4, 'uint16'));
%             resultPtr = libpointer( 'MC06_TAG_S_RESULT', result );
            obj.hDev = zeros(numel(obj.axisNo),1, 'uint32');
            for idxDev=1:numel(obj.axisNo)
                if( obj.enable(idxDev) )
                    hDevPtr  =  libpointer( 'uint32Ptr', obj.hDev(idxDev) );
                    [obj.hDev(idxDev)] = obj.callMC06(FUNC_NAME, obj.boardNo(idxDev), obj.Axis_num(idxDev), hDevPtr);
%                     [retVal, obj.hDev(idxDev), result] = calllib('Mc06A', FUNC_NAME, obj.Boardnum, obj.Axis_num(idxDev), hDevPtr, resultPtr);
%                     obj.assertionMC06(retVal, result); % call error function
                    fprintf('%s successfully opened\n', obj.label{idxDev});
                end
            end
        end
        function BClose(obj)
            %Close(obj) close the opened Device
            %   This function is automatically called by the Destructor, so
            %   you don't need to care about this function
            FUNC_NAME = 'MC06_BClose';
            result = struct('MC06_Result', zeros(1,4, 'uint16'));
            resultPtr = libpointer( 'MC06_TAG_S_RESULT', result );
            for J=1:numel(obj.Axis_num)
                [retVal, result] = calllib('Mc06A', FUNC_NAME, obj.hDev(J), resultPtr);
                obj.assertionMC06(retVal, result); % call error function
            end
        end
        
        %////// 書き込み関連 //////
        function writeMC06(obj, devNum, DriveOrCounter, command, dataarray, senddata )
            arguments
                obj
                devNum
                DriveOrCounter
                command uint16
                dataarray uint16
                senddata 
            end
            DorC = find(strcmpi({'drive', 'counter'}, DriveOrCounter), 1);
            assert(~isempty(DorC), 'DriveOrCounter is not ''drive'' nor ''counter''');
%             result = struct('MC06_Result', zeros(1,4, 'uint16'));
%             resultPtr = libpointer( 'MC06_TAG_S_RESULT', result );
            
            if( DorC == 1 && any(senddata == 1) && any( senddata == 2) && any( sendata == 3) ) 
                % driveデータの場合、すべてのデータを送るコマンドがあるのでそちらを優先
                data = struct('MC06_Data',[dataarray(1), dataarray(2), dataarray(3), uint16(0)]);
                dataPtr = libpointer( 'MC06_TAG_S_DATA', data );
                [~] = obj.callMC06('MC06_IWData', obj.hDev(devNum), dataPtr);
%                 [retVal, ~, result] = calllib('Mc06A', 'MC06_IWData', obj.hDev(devNum), dataPtr, resultPtr);
%                 obj.assertionMC06(retVal, result); % call error function
            else
                funcNames = {...
                    'MC06_BWDriveData1', ...
                    'MC06_BWDriveData2', ...
                    'MC06_BWDriveData3'; ...
                    'MC06_BWCounterData1', ...
                    'MC06_BWCounterData2', ...
                    'MC06_BWCounterData3'};
                for senddata_idx = senddata
                    dataPtr = libpointer('uint16Ptr', dataarray( senddata_idx ));
                    [~] = obj.callMC06(funcNames{DorC, senddata_idx}, obj.hDev(devNum), dataPtr);
%                     [retVal, ~, result] = calllib('Mc06A', funcNames{DorC, senddata_idx}, obj.hDev(devNum), dataPtr, resultPtr);
%                     obj.assertionMC06(retVal, result); % call error function
                end
            end
            
            obj.Wait( devNum, 0 );
            
            switch(DriveOrCounter)
            case 'drive'
                cmdPtr = libpointer('uint16Ptr', command);
                [~] = obj.callMC06('MC06_BWDriveCommand', obj.hDev(devNum), cmdPtr);
%                 [retVal, ~, result] = calllib('Mc06A', 'MC06_BWDriveCommand', obj.hDev(devNum), cmdPtr, resultPtr);
%                 obj.assertionMC06(retVal, result); % call error function
            case 'counter'
                cmdPtr = libpointer('uint16Ptr', command);
                [~] = obj.callMC06('MC06_BWCounterCommand', obj.hDev(devNum), cmdPtr);
%                 [retVal, ~, result] = calllib('Mc06A', 'MC06_BWCounterCommand', obj.hDev(devNum), cmdPtr, resultPtr);
%                 obj.assertionMC06(retVal, result); % call error function
            end
        end

        function [dataarray] = readMC06(obj, devNum, command )
            %MC06コマンド"command"をDRIVE COMMAND PORTに送ったあとに、DRIVE DATA1～DATA3
            %PORTを読み込んで返す。
            result = struct('MC06_Result', zeros(1, 4, 'uint16'));
            resultPtr = libpointer( 'MC06_TAG_S_RESULT', result );
            cmdPtr = libpointer('uint16Ptr', command);
            [retVal, ~, result] = calllib('Mc06A', 'MC06_BWDriveCommand', obj.hDev(devNum), cmdPtr, resultPtr);
            obj.assertionMC06(retVal, result); % call error function
            
            data = struct('MC06_Data', zeros(1, 4, 'uint16'));
            dataPtr = libpointer( 'MC06_TAG_S_DATA', data );
            [retVal, data, result] = calllib('Mc06A', 'MC06_IRDrive', obj.hDev(devNum), dataPtr, resultPtr);
            obj.assertionMC06(retVal, result); % call error function
            dataarray = data.MC06_Data(1:3);
        end
        
        function [varargout] = callMC06(obj, func_name, varargin)
            result = struct('MC06_Result', zeros(1, 4, 'uint16'));
            resultPtr = libpointer( 'MC06_TAG_S_RESULT', result );
            if(nargout == 1)
                switch nargin
                    case 3
                        [retVal, varargout{1}, result] = ...
                            calllib('Mc06A', func_name, varargin{1}, resultPtr);
                    case 4
                        [retVal, varargout{1}, result] = ...
                            calllib('Mc06A', func_name, varargin{1}, varargin{2}, resultPtr);
                    case 5
                        [retVal, varargout{1}, result] = ...
                            calllib('Mc06A', func_name, varargin{1}, varargin{2}, varargin{3}, resultPtr);
                end
            elseif(nargout == 0)
                switch nargin
                    case 3
                        [retVal, result] = ...
                            calllib('Mc06A', func_name, varargin{1}, resultPtr);
                    case 4
                        [retVal, result] = ...
                            calllib('Mc06A', func_name, varargin{1}, varargin{2}, resultPtr);
                    case 5
                        [retVal, result] = ...
                            calllib('Mc06A', func_name, varargin{1}, varargin{2}, varargin{3}, resultPtr);
                end
            end
            obj.assertionMC06(retVal, result); % call error function
            
%             BOpen
%             [retVal, obj.hDev(idxDev), result] 
% = calllib('Mc06A', FUNC_NAME, obj.Boardnum, obj.Axis_num(idxDev), hDevPtr, resultPtr); 
%             Bclose
%             [retVal, result] 
% = calllib('Mc06A', FUNC_NAME, obj.hDev(J), resultPtr);
%             IWData
%             [retVal, ~, result] 
% = calllib('Mc06A', 'MC06_IWData', obj.hDev(devNum), dataPtr, resultPtr);
%             BWDriveDatan
%             [retVal, ~, result] 
% = calllib('Mc06A', funcNames, obj.hDev(devNum), dataPtr, resultPtr);
%             [retVal, ~, result] 
% = calllib('Mc06A', 'MC06_BWDriveCommand', obj.hDev(devNum), cmdPtr, resultPtr);
%             [retVal, ~, result] 
% = calllib('Mc06A', 'MC06_BWCounterCommand', obj.hDev(devNum), cmdPtr, resultPtr);
%             [retVal, ~, result] 
% = calllib('Mc06A', 'MC06_BWDriveCommand', obj.hDev(devNum), cmdPtr, resultPtr);
%             [retVal, data, result] 
% = calllib('Mc06A', 'MC06_IRDrive', obj.hDev(devNum), dataPtr, resultPtr);
%             BWait
%             [retVal, result] 
% = calllib('Mc06A', FUNC_NAME, obj.hDev(num), uint16(Wait_time), resultPtr);
            
        end

        function assertionMC06( obj, retVal, result )
            if(~retVal)
                error( [obj.errorMsg{result.MC06_Result(2)}]);
            end
        end
        
        %////// 読み込み関連 //////
        %////// "Drive speed parameter を設定 //////
        function L_SetDrivePara(obj, num, StartEnd_Vel, Max_Vel, Accel_1, Accel_2)
            % L_SetDrivePara(obj, num, StartEnd_Vel, Max_Vel, Accel_1, Accel_2) sets the L-shape Drive Parameters
            %   StartEnd_Vel : Start&End speed [mm/s] for X,Y,Z or [deg/s] for R,A
            %   Max_Vel      : MAximum speed [mm/s] for X,Y,Z or [deg/s] for R,A
            %   Accel_1&2    : Start&End Acceleration [mm/s^2] for X,Y,Z or [deg/s^2] for R,A
            %   if any argument<=0, the corresponding setting will not be performed.
            assert( nargin==6, 'Wrong number of input arguments'); 
            assertin_oc( StartEnd_Vel, 0, obj.Vel_Max(num));
            assertin_oc( Max_Vel,      0, obj.Vel_Max(num));
            assertin_oc( Accel_1,      0, obj.Accel_Max(num));
            assertin_oc( Accel_2,      0, obj.Accel_Max(num));
            
            LSPD = int32(StartEnd_Vel*obj.Degmm2Pulse(num));   %convert to [Hz: Pulse/s]
            HSPD = Max_Vel*obj.Degmm2Pulse(num);   %convert to [Hz: Pulse/s]
            URATE = 1e6/( Accel_1*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
            DRATE = 1e6/( Accel_2*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
            urateCode = obj.rate2TableNo(URATE);          %rateをTABLE NO.に変換 
            drateCode = obj.rate2TableNo(DRATE);          %rateをTABLE NO.に変換
            
            % LSPD_SET
            dataarray = setdata1_24( LSPD );
            obj.writeMC06(num, 'drive', obj.LSPD_SET, dataarray, [2, 3]);
            % HSPD_SET
            dataarray = setdata1_24( HSPD );
            obj.writeMC06(num, 'drive', obj.HSPD_SET, dataarray, [2, 3]);
            % RATE_SET
            dataarray = setdata_two8( urateCode, drateCode );
            obj.writeMC06(num, 'drive', obj.RATE_SET, dataarray, 3);
        end
        function S_SetDrivePara(obj, num, StartEnd_Vel, Max_Vel, Accel_1, Accel_2, S_Vel1, S_Vel2, S_Vel3, S_Vel4)
            %S_SetDrivePara(obj, num, StartEnd_Vel, Max_Vel, Accel_1, Accel_2, S_Vel1, S_Vel2, S_Vel3, S_Vel4) sets the S-shape Drive Parameters
            %   num          : 1,2,3,4,5
            %   StartEnd_Vel : Start & End velocity [mm/s] or [deg/s]
            %   Max_Vel      : Maximum velocity [mm/s] or [deg/s]
            %   Accel_1      : Start Acceleration [mm/s^2] or [deg/s^2]
            %   Accel_2      : End   Acceleration [mm/s^2] or [deg/s^2]
            %   S_Vel1~4     : velocity of S-shape range [mm/s^2] or [deg/s^2]
            %   if any argument<=0, the corresponding setting will not be performed.
            assert( nargin==10, 'Wrong number of input arguments') ;
            assertin_oc( [StartEnd_Vel, Max_Vel, S_Vel1, S_Vel2, S_Vel3, S_Vel4], 0, obj.Vel_Max(num));
            assertin_oc( [Accel_1, Accel_2],      0, obj.Accel_Max(num));
            
            SLSPD = StartEnd_Vel*obj.Degmm2Pulse(num);  % Setting of StartEnd_Vel:convert to [Hz: Pulse/s]
            SHSPD = Max_Vel*obj.Degmm2Pulse(num);       % Setting of Max_Vel:convert to [Hz: Pulse/s]
            SURATE = 1e6/( Accel_1*obj.Degmm2Pulse(num) ); %Setting of Accel_1: convert to [ms/kHz]
            SDRATE = 1e6/( Accel_2*obj.Degmm2Pulse(num) ); %Setting of Accel_1: convert to [ms/kHz]
            surateCode = obj.rate2TableNo(SURATE);          %rateをTABLE NO.に変換 
            sdrateCode = obj.rate2TableNo(SDRATE);          %rateをTABLE NO.に変換
            
            SCAREA1 = 1e6/( S_Vel1*obj.Degmm2Pulse(num) ); % Setting of S字部分の速度最初の2箇所(SCAREA1): convert to [ms/kHz]
            SCAREA2 = 1e6/( S_Vel2*obj.Degmm2Pulse(num) ); % Setting of S字部分の速度最初の2箇所(SCAREA2):convert to [ms/kHz]
            SCAREA3 = 1e6/( S_Vel3*obj.Degmm2Pulse(num) ); % Setting of S字部分の速度後の2箇所(SCAREA3):convert to [ms/kHz]
            SCAREA4 = 1e6/( S_Vel4*obj.Degmm2Pulse(num) ); % Setting of S字部分の速度後の2箇所(SCAREA4):convert to [ms/kHz]
            assertin( [SCAREA1 SCAREA2 SCAREA3 SCAREA4], 0, 3276750 ); %コード上の限界（下のscarea1Codeなどが0xFFFF = 65535以内でないといけない）
            scarea1Code = uint16(SCAREA1/50);  % setting data = frequency / 50;  see p26 in the manual(command part)
            scarea2Code = uint16(SCAREA2/50);  % setting data = frequency / 50;  see p26 in the manual(command part)
            scarea3Code = uint16(SCAREA3/50);  % setting data = frequency / 50;  see p26 in the manual(command part)
            scarea4Code = uint16(SCAREA4/50);  % setting data = frequency / 50;  see p26 in the manual(command part)
            
            % Setting of StartEnd_Vel
            dataarray = setdata1_24( SLSPD );
            obj.writeMC06(num, 'drive', obj.SLSPD_SET, dataarray, [2, 3]);
            % Setting of Max_Vel
            dataarray = setdata1_24( SHSPD );
            obj.writeMC06(num, 'drive', obj.SHSPD_SET, dataarray, [2, 3]);
            % Setting of Accel_1&2
            dataarray = setdata_two8( surateCode, sdrateCode );
            obj.writeMC06(num, 'drive', obj.SRATE_SET, dataarray, 3);
            % Setting of S字部分の速度最初の2箇所(SCAREA1 & SCAREA2)
            dataarray(2) = scarea2Code; %DATA2がSCAREA2, DATA3がSCAREA1 の順で間違いない。コマンド編マニュアルp26参照
            dataarray(3) = scarea1Code;
            obj.writeMC06(num, 'drive', obj.SCAREA12_SET, dataarray, [2 3])
            % Setting of S字部分のあとの速度2箇所(SCAREA3 & SCAREA4)
            dataarray(2) = scarea3Code;
            dataarray(3) = scarea4Code;
            obj.writeMC06(num, 'drive', obj.SCAREA34_SET, dataarray, [2 3])
        end
        %////// 各種データの読み出しで使用 //////
        function LDriveParameter(obj, num)
            %LDriveParameter(obj, num) outputs the current L Drive Parameters
            fprintf( '\n///// Parameters for Linear Drive /////\n' );
            dataarr = obj.readSetData(num, obj.LSPD_SET ); %LSPD SET
            fprintf(' LSPD(Start Pulse Speed) = %d[Hz]\n', getdata(dataarr, 'uint32'));
            dataarr = obj.readSetData(num, obj.HSPD_SET ); %HSPD SET
            fprintf(' HSPD(Maximum Pulse Speed) = %d[Hz]\n', getdata(dataarr, 'uint32'));
            dataarr = obj.readSetData(num, obj.RATE_SET); %RATE SET
            [urate_code, drate_code ] = getdata_two8( dataarr, 'uint8');
%             fprintf(' URATE(start acceleration): Table NO. %d\n', urate_code);
%             fprintf(' DRATE(end   acceleration): Table NO. %d\n', drate_code);
            fprintf(' URATE(start acceleration): %d[ms/kHz]\n',obj.tableNo2Rate(urate_code));
            fprintf(' DRATE(end   acceleration): %d[ms/kHz]\n',obj.tableNo2Rate(drate_code));
        end
        function SDriveParameter(obj, num)
            %SDriveParameter(obj, num) outputs the current SDrive Parameters
            fprintf( '\n///// Parameters for S-shape Drive /////\n' );
            dataarr = obj.readSetData(num, obj.SLSPD_SET ); %SLSPD SET
            fprintf(' SLSPD(Start Pulse Speed) = %d[Hz]\n', getdata(dataarr, 'uint32'));
            dataarr = obj.readSetData(num, obj.SHSPD_SET ); %SHSPD SET
            fprintf(' SHSPD(Maximum Pulse Speed) = %d[Hz]\n', getdata(dataarr, 'uint32'));
            dataarr = obj.readSetData(num, obj.SRATE_SET); %SRATE SET
            [surate_code, sdrate_code ] = getdata_two8( dataarr, 'uint8');
%             fprintf(' SURATE(start acceleration): Table NO. %d\n', surate_code);
%             fprintf(' SDRATE(end   acceleration): Table NO. %d\n', sdrate_code);
            fprintf(' SURATE(start acceleration): %d[ms/kHz]\n',obj.tableNo2Rate(surate_code));
            fprintf(' SDRATE(end   acceleration): %d[ms/kHz]\n',obj.tableNo2Rate(sdrate_code));
            dataarr = obj.readSetData(num, obj.SCAREA12_SET); %SCAREA12 SET
            fprintf(' SCAREA1 = %d[Hz]\n', dataarr(3)*50);
            fprintf(' SCAREA2 = %d[Hz]\n', dataarr(2)*50);
            dataarr = obj.readSetData(num, obj.SCAREA34_SET); %SCAREA34 SET
            fprintf(' SCAREA3 = %d[Hz]\n', dataarr(2)*50);
            fprintf(' SCAREA4 = %d[Hz]\n', dataarr(3)*50);
        end
        
        function [dataarray] = readSetData(obj, devNum, command_code)
            %readSetData(obj, num, HEX_CODE) reads the data on DRIVE DATA PORT
            %取説(コマンド編) P.71参照
            arguments
                obj
                devNum
                command_code uint16
            end
            result = struct('MC06_Result', zeros(1,4, 'uint16'));
            resultPtr = libpointer( 'MC06_TAG_S_RESULT', result );
            dataPtr = libpointer('uint16Ptr', command_code);
            [retVal, ~, result] = calllib('Mc06A', 'MC06_BWDriveData3', obj.hDev(devNum), dataPtr, resultPtr);
            obj.assertionMC06(retVal, result); % call error function
            
            command1 = obj.SET_DATA_READ;
            cmdPtr = libpointer('uint16Ptr', command1);
            [retVal, ~, result] = calllib('Mc06A', 'MC06_BWDriveCommand', obj.hDev(devNum), cmdPtr, resultPtr);
            obj.assertionMC06(retVal, result); % call error function

            obj.Wait(devNum, 0);
            
            command2 = obj.DATA_READ_PORT_SELECT;
            
            dataarray = obj.readMC06( devNum, command2 );
            
        end
        function tableNo = rate2TableNo(obj, rate )
             [~, idx] = min( abs(obj.RATE_DATA_TABLE_Rate - rate) ); %rateにいちばん近い値を配列RATE_DATA_Table_Rateから検索
             tableNo = obj.RATE_DATA_TABLE_No(idx);
        end
        function rate = tableNo2Rate(obj, tableNo )
             rate = obj.RATE_DATA_TABLE_Rate(tableNo + 1);
        end
        
    end
    properties(Constant)
        % MCC06 general DRIVE COMMAND
        NO_OPERATION = 0x0000;
        SPEC_INITIALIZE1 = 0x0001;
        SPEC_INITIALIZE2 = 0x0002;
        SPEC_INITIALIZE3 = 0x0003;
        DRIVE_DELAY_SET = 0x0007;
        CW_SOFT_LIMIT_SET = 0x0008;
        CCW_SOFT_LIMIT_SET = 0x0009;
        LSPD_SET = 0x0010;
        HSPD_SET = 0x0011;
        ELSPD_SET = 0x0012;
        RATE_SET = 0x0013;
        END_PULSE_SET = 0x0018;
        ESPD_SET = 0x0019;
        ESPD_DELAY_SET = 0x001A;
        RATE_DATA_SET = 0x001E;
        DOWN_POINT_SET = 0x001F;
        PLUSJOG = 0x0020;
        MINUSJOG = 0x0021;
        PLUSSCAN = 0x0022;
        MINUSSCAN = 0x0023;
        INC_INDEX = 0x0024;
        ABS_INDEX = 0x0025;
        SLSPD_SET = 0x0030;
        SHSPD_SET = 0x0031;
        SELSPD_SET = 0x0032;
        SRATE_SET = 0x0033;
        SCAREA12_SET = 0x0034;
        SCAREA34_SET = 0x0035;
        SEND_PULSE_SET = 0x0038;
        SESPD_SET = 0x0039;
        SESPD_DELAY_SET = 0x003A;
        SRATE_DATA_SET = 0x003E;
        SRATE_DOWN_POINT = 0x003F;
        PLUS_SRATE_SCAN = 0x0042;
        MINUS_SRATE_SCAN = 0x0043;
        INC_SRATE_INDEX = 0x0044;
        ABS_SRATE_INDEX = 0x0045;
        ORIGIN_SPEC_SET_ORIGIN = 0x0060;
        ORIGIN_CSPD_SET_CONSTANT_SCAN = 0x0061;
        ORIGIN_DELAY_SET = 0x0062;
        ORIGIN_OFFSET_PULSE_SET = 0x0063;
        ORIGIN_CSCAN_ERROR_PULSE_SET_CONSTANT_SCAN = 0x0064;
        ORIGIN_JOG_ERROR_PULSE_SET_JOG = 0x0065;
        ORIGIN_PRESET_PULSE_SET_PRESET_ORIGIN = 0x0068;
        ORIGIN = 0x0070;
        SRATE_ORIGIN = 0x0071;
        PRESET_ORIGIN = 0x0074;
        SRATE_PRESET_ORIGIN = 0x0075;
        STBY_SPEC_SET_STBY = 0x0080;
        SERVO_SPEC_SET = 0x0082;
        DEND_TIME_SET_DEND = 0x0083;
        ERROR_STATUS_READ = 0x0088;
        SET_DATA_READ = 0x0089;
        PLUS_SENSOR_SCAN1 = 0x0090;
        MINUS_SENSOR_SCAN1 = 0x0091;
        SENSOR_INDEX1 = 0x0094;
        SENSOR_INDEX2 = 0x0095;
        SENSOR_INDEX3 = 0x0096;
        PLUS_SRATE_SENSOR_SCAN1 = 0x0098;
        MINUS_SRATE_SENSOR_SCAN1 = 0x0099;
        SRATE_SENSOR_INDEX1 = 0x009C;
        SRATE_SENSOR_INDEX2 = 0x009D;
        SRATE_SENSOR_INDEX3 = 0x009E;
        CHANGE_POINT_SET = 0x00B0;
        CHANGE_DATA_SET = 0x00B1;
        AUTO_CHANGE_DRIVE_SET = 0x00B7;
        PLUS_AUTO_CHANGE_SCAN = 0x00B8;
        MINUS_AUTO_CHANGE_SCAN = 0x00B9;
        AUTO_CHANGE_INC_INDEX = 0x00BA;
        AUTO_CHANGE_ABS_INDEX = 0x00BB;
        CENTER_POSITION_SET = 0x0100;
        PASS_POSITOIN_SET = 0x0101;
        CP_SPEC_SET = 0x010F;
        ABS_STRAIGHT_CP = 0x0110;
        ABS_SRATE_STRAIGHT_CP = 0x0111;
        ABS_STRAIGHT_CONST_CP = 0x0112;
        ABS_SRATE_STRAIGHT_CONST_CP = 0x0113;
        PLUS_ABS_CIRCULAR_CP = 0x0120;
        MINUS_ABS_CIRCULAR_CP = 0x0121;
        PLUS_ABS_SRATE_CIRCULAR_CP = 0x0122;
        MINUS_ABS_SRATE_CIRCULAR_CP = 0x0123;
        PLUS_ABS_CIRCULAR_CONST_CP = 0x0124;
        MINUS_ABS_CIRCULAR_CONST_CP = 0x0125;
        PLUS_ABS_SRATE_CIRCULAR_CONST_CP = 0x0126;
        MINUS_ABS_SRATE_CIRCULAR_CONST_CP = 0x0127;
        ABS_CIRCULAR2_CP = 0x0130;
        ABS_SRATE_CIRCULAR2_CP = 0x0131;
        ABS_CIRCULAR2_CONST_CP = 0x0132;
        ABS_SRATE_CIRCULAR2_CONST_CP = 0x0133;
        ABS_CIRCULAR3_CP = 0x0138;
        ABS_SRATE_CIRCULAR3_CP = 0x0139;
        ABS_CIRCULAR3_CONST_CP = 0x013A;
        ABS_SRATE_CIRCULAR3_CONST_CP = 0x013B;
        INC_STRAIGHT_CP = 0x0150;
        INC_SRATE_STRAIGHT_CP = 0x0151;
        INC_STRAIGHT_CONST_CP = 0x0152;
        INC_SRATE_STRAIGHT_CONST_CP = 0x0153;
        PLUS_INC_CIRCULAR_CP = 0x0160;
        MINUS_INC_CIRCULAR_CP = 0x0161;
        PLUS_INC_SRATE_CIRCULAR_CP = 0x0162;
        MINUS_INC_SRATE_CIRCULAR_CP = 0x0163;
        PLUS_INC_CIRCULAR_CONST_CP = 0x0164;
        MINUS_INC_CIRCULAR_CONST_CP = 0x0165;
        PLUS_INC_SRATE_CIRCULAR_CONST_CP = 0x0166;
        MINUS_INC_SRATE_CIRCULAR_CONST_CP = 0x0167;
        INC_CIRCULAR2_CP = 0x0170;
        INC_SRATE_CIRCULAR2_CP = 0x0171;
        INC_CIRCULAR2_CONST_CP = 0x0172;
        INC_SRATE_CIRCULAR2_CONST_CP = 0x0173;
        INC_CIRCULAR3_CP = 0x0178;
        INC_SRATE_CIRCULAR3_CP = 0x0179;
        INC_CIRCULAR3_CONST_CP = 0x017A;
        INC_SRATE_CIRCULAR3_CONST_CP = 0x017B;
        MULTICHIP_STRAIGHT_CP = 0x0190;
        MULTICHIP_SRATE_STRAIGHT_CP = 0x0191;
        PLUS_MULTICHIP_CIRCULAR_CP = 0x01A0;
        MINUS_MULTICHIP_CIRCULAR_CP = 0x01A1;
        PLUS_MULTICHIP_SRATE_CIRCULAR_CP = 0x01A2;
        MINUS_MULTICHIP_SRATE_CIRCULAR_CP = 0x01A3;
        PLUS_MULTICHIP_CIRCULAR_CONST_CP = 0x01A4;
        MINUS_MULTICHIP_CIRCULAR_CONST_CP = 0x01A5;
        PLUS_MULTICHIP_SRATE_CIRCULAR_CONST_CP = 0x01A6;
        MINUS_MULTICHIP_SRATE_CIRCULAR_CONST_CP = 0x01A7;
        
        %MCC06 special DRIVE COMMAND
        HARD_INITIALIZE1 = 0xF001;
        HARD_INITIALIZE2 = 0xF006;
        HARD_INITIALIZE6 = 0xF006;
        HARD_INITIALIZE7 = 0xF007;
        SIGNAL_OUT = 0xF00C;
        DRST = 0xF00D;
        SLOW_STOP = 0xF00E;
        FAST_STOP = 0xF00F;
        ADDRESS_COUNTER_INITIALIZE1 = 0xF010;
        ADDRESS_COUNTER_INITIALIZE2 = 0xF011;
        ADDRESS_COUNTER_INITIALIZE3 = 0xF012;
        PULSE_COUNTER_INITIALIZE1 = 0xF014;
        PULSE_COUNTER_INITIALIZE2 = 0xF015;
        PULSE_COUNTER_INITIALIZE3 = 0xF016;
        DFL_COUNTER_INITIALIZE1 = 0xF018;
        DFL_COUNTER_INITIALIZE2 = 0xF019;
        DFL_COUNTER_INITIALIZE3 = 0xF01A;
        SPEED_COUNTER_INITIALIZE1 = 0xF01C;
        SPEED_COUNTER_INITIALIZE2 = 0xF01D;
        SPEED_COUNTER_INITIALIZE3 = 0xF01E;
        INT_FACTOR_CLR = 0xF020;
        INT_FACTOR_MASK = 0xF021;
        COUNTER_COMP_MASK = 0xF023;
        COUNT_LATCH_SPEC_SET = 0xF028;
        UDC_SPEC_SET = 0xF030;
        SPEED_CHANGE_SPEC_SET = 0xF031;
        INDEX_CHANGE_SPEC_SET = 0xF033;
        UP_DRIVE = 0xF034;
        DOWN_DRIVE = 0xF035;
        CONST_DRIVE = 0xF036;
        SPEED_CHANGE = 0xF038;
        RATE_CHANGE = 0xF03A;
        INC_INDEX_CHANGE = 0xF03C;
        ABS_INDEX_CHANGE = 0xF03D;
        PLS_INDEX_CHANGE = 0xF03E;
        MCC_SPEED_PORT_SELECT = 0xF040;
        DATA_READ_PORT_SELECT = 0xF041;
        ADDRESS_COUNTER_PORT_SELECT = 0xF048;
        PULSE_COUNTER_PORT_SELECT = 0xF049;
        DFL_COUNTER_PORT_SELECT = 0xF04A;
        SPEED_COUNTER_PORT_SELECT = 0xF04B;
        ADDRESS_LATCH_DATA_PORT_SELECT = 0xF04C;
        PULSE_LATCH_DATA_PORT_SELECT = 0xF04D;
        DFL_LATCH_DATA_PORT_SELECT = 0xF04E;
        SPEED_LATCH_DATA_PORT_SELECT = 0xF04F;
        
        % MCC06 general COUNTER COMMAND
        ADDRESS_COUNTER_PRESET = 0x0000;
        ADDRESS_COUNTER_MAX_COUNT_SET = 0x000A;
        
        % MCC06 special COUNTER COMMAND
        ADDRESS_COUNTER_COMPARE_REGISTER1_SET = 0x0001;
        ADDRESS_COUNTER_COMPARE_REGISTER2_SET = 0x0002;
        ADDRESS_COUNTER_COMPARE_REGISTER3_SET = 0x0003;
        PULSE_COUNTER_PRESET = 0x0010;
        PULSE_COUNTER_COMPARE_REGISTER1_SET = 0x0011;
        PULSE_COUNTER_COMPARE_REGISTER2_SET = 0x0012;
        PULSE_COUNTER_COMPARE_REGISTER3_SET = 0x0013;
        PULSE_COUNTER_MAX_COUNT_SET = 0x001A;
        DFL_COUNTER_PRESET = 0x0020;
        DFL_COUNTER_COMPARE_REGISTER1_SET = 0x0021;
        DFL_COUNTER_COMPARE_REGISTER2_SET = 0x0022;
        DFL_COUNTER_COMPARE_REGISTER3_SET = 0x0023;
        DFL_COUNTER_MAX_COUNT_SET = 0x002A;
        SPEED_COUNTER_COMPARE_REGISTER1_SET = 0x0031;
        SPEED_COUNTER_COMPARE_REGISTER2_SET = 0x0032;
        SPEED_COUNTER_COMPARE_REGISTER3_SET = 0x0033;
        SPEED_OVF_COUNT_SET = 0x003A;
        
        % HARD CONFIGURATION COMMAND
        HARD_CONFIGURATION1 = 0x0001;
        HARD_CONFIGURATION2 = 0x0002;
        HARD_CONFIGURATION3 = 0x0003;
        HARD_CONFIGURATION4 = 0x0004;
        HARD_CONFIGURATION5 = 0x0005;
        HARD_CONFIGURATION6 = 0x0006;
        PAUSE_SET_SPEC = 0x0010;
        PAUSE_CLR_SPEC = 0x0011;
        PAUSE = 0x0012;
        HARD_CONFIGURATION_SET_DATA_READ = 0x0020;
        GPOUT = 0x0021;

        %　パルスレートのテーブル：取説 8-1ドライブの基本パラメータを設定する(4) P.46参照
        RATE_DATA_TABLE_No = uint8(0x00:0x73);
        RATE_DATA_TABLE_Rate = [...
            1000 910 820 750 680 620 560 510 470 430 390 360 330 300 270 240 220 200 180 160 150 130 120 110 ...
             100  91  82  75  68  62  56  51  47  43  39  36  33  30  27  24  22  20  18  16  15  13  12  11 ...
              10 9.1 8.2 7.5 6.8 6.2 5.6 5.1 4.7 4.3 3.9 3.6 3.3 3.0 2.7 2.4 2.2 2.0 1.8 1.6 1.5 1.3 1.2 1.1 ...
             1.0 .91 .82 .75 .68 .62 .56 .51 .47 .43 .39 .36 .33 .30 .27 .24 .22 .20 .18 .16 .15 .13 .12 .11 ...
             .10 .091 .082 .075 .068 .062 .056 .051 .047 .043 .039 .036 .033 .030 .027 .024 .022 .020 .018 .016]; %設定可能な加速度[ms/kHz]の一覧
        
        errorMsg = {... %error message in sResult struct
            'invalid error message', ...
            'DLL内部でAPIエラーが発生しました。' ...
            'NULLポインタが指定されました。', ...
            'C-V870.sys／C-V872.sysがロードされていません。', ...
            '指定されたボード番号に誤りがあります。', ...
            '軸の指定に誤りがあります。', ...
            'デバイスハンドルの内容が異常です。', ...
            'デバイスに空きがないため、オープンできません。', ...
            '指定されたデバイスは、オープンされていません。', ...
            '指定されたデバイスは、すでにオープンされています。', ...
            'READY WAIT関数がTIME OVERで終了しています。', ...
            'WM_QUITメッセージを受信しました。', ...
            'READY WAIT中にREADY WAIT中止関数が実行されました。', ...
            '同一デバイスのREADY WAIT関数が複数同時に実行されました。', ...
            'ボードが１枚も検出できません。', ...
            '検出したボード枚数が10枚を超えました。', ...
            '指定されたボード番号に該当するボードがありません。', ...
            'ボード番号が重複しています。', ...
            '原因不明のエラーが発生しました。', ...
            '指定された割り込みはすでに設定されています。', ...
            'INTの指定に誤りがあります。', ...
            'すでに指定したINTは、設定されています。', ...
            '割り込みがクローズされていません。', ...
            'INT FACTORの指定に誤りがあります。', ...
            '割り込みがオープンされていません。', ...
            'INTの設定が行われていません。', ...
            '指定したMCC06のSTATUS1 PORT BUSY=1である為、関数の実行が出来ません。', ...
            'C-V870.sys/C-V872.sys内部でMCC06にCOMMANDを書き込んだ後、STATUS1 PORT BUSY=0の確認を行っていましたが、100ms待ってもBUSY=0にならない為、関数の実行を中止しました。' ...
        };
            
    end

end %class



