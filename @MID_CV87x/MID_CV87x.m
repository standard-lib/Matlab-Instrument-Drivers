classdef MID_CV87x < handle
    % Scanner class
    %   obj = MID_CV87x()でインスタンスを定義
    %   例：
    %       PS = C_V87xclass();--------------------オブジェクトPSを作成
    %       PS.Address_Reset('Y');----------------アドレスをリセット
    %       PS.SetDriveSpeed('S', 'Y', 'fast');---Y軸のS字ドライブ速度を'fast'に設定
    %       PS.Drive('Y', 'absS', 30);------------Y軸のS字ドライブ(+30mm)を実行
    % 変更したいこと一覧(2018松田）
    % ・全体的にメソッドが多すぎる．もちょっと共通化してスリムにしたい．
    % ・可動域制限とか速度制限とかはscanner.confからデフォルトで読み込みたい．
    % ・Boardnumは軸の数だけ用意されるべきで，０を仮定したくない．
    % ・sResultなどは配列である必要はない．各呼び出しに対して使い捨てで構わない．
    % ・Drive速度などをscanner.confを読み込んで決めさせたい．
    % ・軸の名前を strfind('XYZRA',
    % upper(num))で軸番号に変換しているが，軸の名前はscanner.confで決めたい
    % ・プログラム中に可能な限りリテラルの数字を書かない．おそらくscanner.confから読み取れる値のはず．
    % ・ジョグモードを追加したい．PS.jog()を実行すると，Escを押すまで，キー待ちをして，
    % F1:第1軸＋，F2:第1軸－，F3：第2軸＋．．．のようなジョグを行う．ショートカットキーはInsight Scanに準拠する．
    properties(SetAccess = private)
        sResult;    % 各コマンドで結果を格納する構造体(ヘッダ参照)
        sResultPtr; % 構造体のポインタ
        sData ;     % 各コマンドでデータを格納する構造体(ヘッダ参照)
        sDataPtr;   % 構造体のポインタ
        hDev;       % デバイス変数(32ビット符号なし整数DWORD)
        hDevPtr;    % デバイス変数ポインタ
        Degmm2Pulse % 1Degree or 1mm が何パルスに対応するか
        Move_Limit; %可動域制限:   あやまって大きく動かしすぎないように保険を掛ける
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
        Boardnum = uint16(0); % 2014/7/26現在Board numberは0だけ
        RATE_DATA = [ 910 820 750 680 620 560 510 470 430 390 360 ...
              330 300 270 240 220 200 180 160 150 130 120 110 ...
              100  91  82  75  68  62  56  51  47  43  39  36 ...
               33  30  27  24  22  20  18  16  15  13  12  11 ...
               10 9.1 8.2 7.5 6.8 6.2 5.6 5.1 4.7 4.3 3.9 3.6 ...
               3.3]; %設定可能な加速度[ms/kHz]の一覧
    end
   
    methods
        %////// コンストラクタ //////
        function obj = MID_CV87x()
            if (~libisloaded('Mc06A'))
                loadlibrary('Mc06A','Mc06A.h');
            end
            obj.Axis_num = uint32([0 1 2 3]);
            obj.Axis_char = 'XYZR';
            %ポインタの生成
            obj.hDev       =  uint32(0);  %BOpenで割り当てられるのでここでは適当な値
            obj.hDevPtr    =  libpointer( 'uint32Ptr', obj.hDev );
            obj.sResult    = struct('MC06_Result', zeros(1,4, 'uint16'));
            obj.sResultPtr = libpointer( 'MC06_TAG_S_RESULT', obj.sResult );
            obj.sData      = struct('MC06_Data',zeros(1,4,'uint16'));
            obj.sDataPtr   = libpointer( 'MC06_TAG_S_DATA', obj.sData );

            for J=1:numel(obj.Axis_num)
                obj.hDev(J)       =  uint32(0);  %BOpenで割り当てられるのでここでは適当な値
                obj.hDevPtr(J)    =  libpointer( 'uint32Ptr', obj.hDev(J) );
            end
            
            for J=1:numel(obj.Axis_num)
                obj.sResult(J)    =  struct('MC06_Result', zeros(1,4, 'uint16'));
                obj.sResultPtr(J) =  libpointer( 'MC06_TAG_S_RESULT', obj.sResult(J) );
                obj.sData(J)      =  struct('MC06_Data',zeros(1,4,'uint16'));
                obj.sDataPtr(J)   =  libpointer( 'MC06_TAG_S_DATA', obj.sData(J) );
            end
            obj.Degmm2Pulse = [1000, 1000, 5000, 100000/360];  %[Pulse/mm, Pulse/mm, Pulse/mm, Pulse/deg, Pulse/deg]
                                                                             %X,Y: 500*40/10,  基本ステップ角:500Pulse/Rev, 分割設定:1/40,  ねじピッチ:10mm
                                                                             %Z  : 200*100/2,  基本ステップ角:200Pulse/Rev, 分割設定:1/100, ねじピッチ:2mm
                                                                             %R,A: 500*200/360,基本ステップ角:500Pulse/Rev, 分割設定:1/200
            obj.Move_Limit = [ 713,  468, 310, 180];          %[mm, mm, mm, deg]
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

            obj.BOpen; %デバイスオープン            
            obj.SetDriveSpeed('L', 'X', 'slow'); %すべての drive speed を'slow'に初期化
            obj.SetDriveSpeed('L', 'Y', 'slow');
            obj.SetDriveSpeed('L', 'Z', 'slow');            
            obj.SetDriveSpeed('L', 'R', 'slow');
            obj.SetDriveSpeed('S', 'X', 'slow');
            obj.SetDriveSpeed('S', 'Y', 'slow');
            obj.SetDriveSpeed('S', 'Z', 'slow');
            obj.SetDriveSpeed('S', 'R', 'slow');
            
            % 第4軸は北條研の装置では，ストッパの論理がデフォルトとは逆なので，必ず直させる．
            obj.BWDriveData(4, 3, 'FFF3');     % Statusを見に行かない．ちょっとお行儀悪い．
            obj.BWDriveCommand(4, 'F007');
          %      obj.Address_Reset( 'X','Y','Z','R','A' ); %原点設定
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
                obj.Wait(num, 0);
                obj.SetData1(num, 0);
                obj.IWCounter(num, '0000');
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

            FUNC_NAME = 'MC06_BWaitDriveCommand';
            Wait_time = 0;
            if ~isempty(varargin), Wait_time = varargin{1}; end
            if Wait_time<0, Wait_time = 0; end

            [temp, obj.sResult(num)] = calllib('Mc06A', FUNC_NAME, obj.hDev(num), uint16(Wait_time), obj.sResultPtr(num));
            if ~temp || obj.sResult(num).MC06_Result(2)
                error('Error occured during %s\n temp=%d, sResult(%d).(2)=%d', FUNC_NAME, temp, num, obj.sResult(num).MC06_Result(2));
            end
        end
        function Address_Reset(obj, varargin)
            %Address_Reset(obj, num) sets the current position as origin.
            %   引数: 1, 2, 3, 4, 5 or 'X', 'Y', 'Z', 'R', 'A' これ以外は無視
            %   引数は何個でもOK
            %   ex)  obj.Address_Reset( 'X', 'Z', 'A' ),
            %        obj.Address_Reset( 1, 2, 3 )
            %   You'd better use this when 'AbsDrive' is excuted.

            for J=1:numel(varargin)
                if ischar(varargin{J})
                    num = int32( strfind('XYZRA', upper(varargin{J})) ); %文字列の場合 ==> 番号に変換
                else
                    num = varargin{J};
                end 
                if num>=1 && num<=5
                    obj.Wait(num, 0);
                    obj.SetData1(num, 0);
                    obj.IWCounter(num, '0000');
                end
            end

        end
        function ScanStop(obj, num)
            %ScanStop(obj, num) stops the scan right now
            %   num: 1, 2, 3, 4, 5 or 'X', 'Y', 'Z', 'R', 'A' 
            if ischar(num), num = int32( strfind('XYZRA', upper(num)) ); end %numが文字列の場合 ==> 番号に変換
            if num<1 || num>5 || isempty(num)
                fprintf('Invalid argument. 1~5 or ''X'',''Y'',''Z'',''R'',''A'' is accepted.');
                return
            end
            obj.BWDriveCommand(num, 'F00F');
        end

        %////// ScanDrive関連 (HEX CODE: 0020~0025, 0042~0045) //////
        function Drive(obj, Axisname, SCAN_TYPE, varargin)
            %Drive(obj, Axisname, SCAN_TYPE, varargin) excutes the drive
            %   Axisname  : 'X', 'Y', 'Z', 'R', or 'A'
            %   SCAN_TYPE : '+J'   :  +Jog Drive
            %               '-J'   :  -Jog Drive
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
                fprintf('Axisname has to be ''X'',''Y'',''Z'',''R'', or ''A''\n');
            else
                switch SCAN_TYPE
                    case '+J'
                        obj.Jog_plus(num);
                    case '-J'
                        obj.Jog_minus(num);
                    case '+L'
                        obj.L_Scan_plus(num);
                    case '-L'
                        obj.L_Scan_minus(num);
                    case 'incL'
                        obj.L_IncDrive(num, varargin{1});
                    case 'absL'
                        obj.L_AbsDrive(num, varargin{1});
                    case '+S'
                        obj.S_Scan_plus(num);
                    case '-S'
                        obj.S_Scan_minus(num);
                    case 'incS'
                        obj.S_IncDrive(num, varargin{1});
                    case 'absS'
                        obj.S_AbsDrive(num, varargin{1});
                    otherwise
                        fprintf('invalid ''SCANTYPE''\n');
                end
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
            if nargin~=4, error('Wrong number of input arguments') ; end
            
            num = int32( strfind('XYZRA', upper(Axisname)) ); %これでX,Y,Z,R,Aを1,2,3,4,5に対応付けできる
            if isempty(num)
                fprintf('Axisname has to be ''X'',''Y'',''Z'',''R'', or ''A''\n');
            else
                if strcmp(LorS, 'L')
                    obj.L_SetDriveSpeed(num, Speed);
                elseif strcmp(LorS, 'S')
                    obj.S_SetDriveSpeed(num, Speed);
                else
                    fprintf('1st argument has to be ''L'' or ''S''\n');
                end
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
            fprintf('\nC_V872 stepping motor controller was successifully closed\n');
        end      
%    end %methods

%    methods( Access = private ) %外部からは参照することのない関数
        function BOpen(obj)
            %Open(obj) opens a Device
            %   This function is automatically called by the Constructor, so
            %   you don't need to care about this function
            FUNC_NAME = 'MC06_BOpen';
            for J=1:numel(obj.Axis_num)
                [temp, obj.hDev(J), obj.sResult(J)] = calllib('Mc06A', FUNC_NAME, obj.Boardnum, obj.Axis_num(J), obj.hDevPtr(J), obj.sResultPtr(J));
                if ~temp || obj.sResult(J).MC06_Result(2)
                    disp(obj.sResult(J));
                    error('Error occured during %s\n temp=%d, sResult(%d).(2)=%d', FUNC_NAME, temp, J, obj.sResult(J).MC06_Result(2));
                else
                   %fprintf('hDev=%d, sResult=[%d,%d,%d,%d]\n', obj.hDev(J), obj.sResult.MC06_Result(J,:)); 
                    %disp(['MC06_BOpen done' char(10)])
                end
            end
            fprintf('All devices were successfully opened\n');
        end
        function BClose(obj)
            %Close(obj) close the opened Device
            %   This function is automatically called by the Destructor, so
            %   you don't need to care about this function
            FUNC_NAME = 'MC06_BClose';
            for J=1:numel(obj.Axis_num)
                [temp, obj.sResult(J)] = calllib('Mc06A', FUNC_NAME, obj.hDev(J), obj.sResultPtr(J));
                if ~temp || obj.sResult(J).MC06_Result(2)
                    if obj.sResult(J).MC06_Result(2)==7
                        error('(BClose) Device handle is abnormal. File is not opened from the first.');
                    else
                        error(['Error occured (BClose)' char(10)]);
                    end
                else
                % disp(['MC06_BClose done' char(10)])    
                end
            end
        end
        %////// 書き込み関連 //////
        function IWDrive(obj, num, HEX_CODE)
            %IWDrive(obj, num, 'HEX_CODE') writes in a lump the Command Code&Data on the
            %DRIVE COMMAND&DATA PORT 1,2,3
            if nargin~=3, error('Wrong number of input arguments') ; end
            
            FUNC_NAME = 'MC06_IWDrive';
            Cmd = uint16( hex2dec(HEX_CODE) ); %HEX CODE (16進数)
            [temp, obj.sData(num), obj.sResult(num)] = calllib('Mc06A', FUNC_NAME, obj.hDev(num), Cmd, obj.sDataPtr(num), obj.sResultPtr(num));
            if ~temp || obj.sResult(num).MC06_Result(2)
                error('Error occured during %s\n temp=%d, sResult(%d).(2)=%d', FUNC_NAME,temp, num, obj.sResult(num).MC06_Result(2))
            end          
        end
        function IWData(obj, num)
            %IWData(obj, num) writes the Command Data on the DRIVE COMMAND DATA
            %PORT 1,2,3
            if nargin~=2, error('Wrong number of input arguments') ; end
            FUNC_NAME = 'MC06_IWData';
            [temp, obj.sData(num), obj.sResult(num)] = calllib('Mc06A', FUNC_NAME, obj.hDev(num), obj.sDataPtr(num), obj.sResultPtr(num));
            if ~temp || obj.sResult(num).MC06_Result(2)
                error('Error occured during %s\n temp=%d, sResult(%d).(2)=%d', FUNC_NAME, temp, num, obj.sResult(num).MC06_Result(2))
            end          
        end
        function BWDriveCommand(obj, num, HEX_CODE)
            %BWDriveCommand(obj, num, 'HEX_CODE') writes the Command Code on the DRIVE COMMAND PORT
            if nargin~=3, error('Wrong number of input arguments') ; end
            
            FUNC_NAME = 'MC06_BWDriveCommand';
            Cmd = uint16( hex2dec(HEX_CODE) ); %HEX CODEを10進数のuint16に
            CmdPtr = libpointer('uint16Ptr', Cmd); %HEX CODEのポインタ
            [temp, ~, obj.sResult(num)] = calllib('Mc06A', FUNC_NAME, obj.hDev(num), CmdPtr, obj.sResultPtr(num));
            if ~temp || obj.sResult(num).MC06_Result(2)
                error('Error occured during %s\n temp=%d, sResult(%d).(2)=%d',  FUNC_NAME, temp, num, obj.sResult(num).MC06_Result(2))
            end            
        end
        function BWDriveData(obj, num, number, HEX_CODE)
            %BWDriveData(obj, num, number, HEX_CODE) writes the 'HEX_CODE' on the DRIVE DATA PORT 'number'
            
            if nargin == 4
                switch number
                    case 1
                        FUNC_NAME = 'MC06_BWDriveData1';
                    case 2
                        FUNC_NAME = 'MC06_BWDriveData2';
                    case 3
                        FUNC_NAME = 'MC06_BWDriveData3';
                    otherwise
                        error('DrivePort Number has to be 1, 2, or 3')
                end
                Cmd = uint16( hex2dec(HEX_CODE) );
                pDataPtr = libpointer('uint16Ptr', Cmd);
                [temp, ~, obj.sResult(num)] = calllib('Mc06A', FUNC_NAME, obj.hDev(num), pDataPtr, obj.sResultPtr(num));
                if ~temp || obj.sResult(num).MC06_Result(2)
                    error('Error occured during %s\n temp=%d, sResult(%d).(2)=%d', FUNC_NAME, temp, num, obj.sResult(num).MC06_Result(2))
                end
            else
               error('Wrong number of input arguments(BWDriveData)') 
            end
        end
        function IWCounter(obj, num,  HEX_CODE)
            %IWCounter(obj, num, 'HEX_CODE') writes in a lump the Counter Code&Data on the
            %COUNTER COMMAND&DATA PORT(1,2,3)
            if nargin~=3, error('Wrong number of input arguments') ; end

            FUNC_NAME = 'MC06_IWCounter';
            Cmd = uint16( hex2dec(HEX_CODE) ); %HEX CODE (16進数)
            [temp, obj.sData(num), obj.sResult(num)] = calllib('Mc06A', FUNC_NAME, obj.hDev(num), Cmd, obj.sDataPtr(num), obj.sResultPtr(num));
            if ~temp || obj.sResult(num).MC06_Result(2)
                error('Error occured during %s\n temp=%d, sResult(%d).(2)=%d', FUNC_NAME,temp, num, obj.sResult(num).MC06_Result(2))
            end          
        end
        function BWCounterCommand(obj, num, HEX_CODE)
            %BWCounterCommand(obj, num, 'HEX_CODE') writes the Command Code on the COUNTER COMMAND PORT
            if nargin~=3, error('Wrong number of input arguments') ; end
            FUNC_NAME = 'MC06_BWCounterCommand';

            Cmd = uint16( hex2dec(HEX_CODE) ); %HEX CODEを10進数のuint16に
            CmdPtr = libpointer('uint16Ptr', Cmd); %HEX CODEのポインタ
            [temp, ~, obj.sResult(num)] = calllib('Mc06A', FUNC_NAME, obj.hDev(num), CmdPtr, obj.sResultPtr(num));
            if ~temp || obj.sResult(num).MC06_Result(2)
                error('Error occured during %s\n temp=%d, sResult(%d).(2)=%d',  FUNC_NAME, temp, num, obj.sResult(num).MC06_Result(2))
            end            
        end       
        function BWCounterData(obj, num, number, pData)
            %BWCounterData(obj, num, number, pData) writes the 'pData' on the DRIVE DATA PORT 'number'
            if nargin == 4
                switch number
                    case 1
                        FUNC_NAME = 'MC06_BWCounterData1';
                    case 2
                        FUNC_NAME = 'MC06_BWCounterData2';
                    case 3
                        FUNC_NAME = 'MC06_BWCounterData3';
                    otherwise
                        error('DrivePort Number has to be 1, 2, or 3')
                end
                pDataPtr = libpointer('uint16Ptr', pData);
                [temp, ~, obj.sResult(num)] = calllib('Mc06A', FUNC_NAME, obj.hDev(num), pDataPtr, obj.sResultPtr(num));
                if ~temp || obj.sResult(num).MC06_Result(2)
                    error('Error occured during %s\n temp=%d, sResult(%d).(2)=%d', FUNC_NAME, temp, num, obj.sResult(num).MC06_Result(2));
                end
            else
               error('Wrong number of input arguments(BWDriveData)') 
            end
        end
        function SetData1(obj, num, pData)
            %SetData1(obj, num, pData) calls 'MC06_SetData1'
            if nargin~=3, error('Wrong number of input arguments') ; end
            obj.sData(num) = calllib('Mc06A', 'MC06_SetData1', uint32(pData), obj.sDataPtr(num));
        end
        function pData = GetData(obj, num)
            %GetData(obj, num) calls 'MC06_GetData'
            [pData, ~] = calllib('Mc06A', 'MC06_GetData', obj.sDataPtr(num));
        end
        
        %////// 読み込み関連 //////
        function psData = BRStatus(obj, num, number)
            %psData = BRStatus(obj, num, number) reads the data from STATUS (number) PORT
            if nargin == 3
                switch number
                    case 1
                        FUNC_NAME = 'MC06_BRStatus1';
                    case 2
                        FUNC_NAME = 'MC06_BRStatus2';
                    case 3
                        FUNC_NAME = 'MC06_BRStatus3';
                    case 4
                        FUNC_NAME = 'MC06_BRStatus4';
                    case 5
                        FUNC_NAME = 'MC06_BRStatus5';
                    otherwise
                        error('STATUS PORT Number has to be 1, 2, 3, 4, or 5');
                end
                psData = uint16(0);
                psDataPtr = libpointer('uint16Ptr', psData);
                [temp, psData, obj.sResult(num)] = calllib('Mc06A', FUNC_NAME, obj.hDev(num), psDataPtr, obj.sResultPtr(num));
                if ~temp || obj.sResult(num).MC06_Result(2)
                    error('Error occured during %s\n temp=%d, sResult(%d).(2)=%d', FUNC_NAME, temp, num, obj.sResult(num).MC06_Result(2));
                end
            else
               error('Wrong number of input arguments(BWDriveData)') ;
            end
        end
        function IRDrive(obj, num)
            %IRDrive(obj, num) reads in a lump the data from DRIVE DATA 1,2,3 PORT
            FUNC_NAME = 'MC06_IRDrive';
            [temp, obj.sData(num), obj.sResult(num)] = calllib('Mc06A', FUNC_NAME, obj.hDev(num), obj.sDataPtr(num), obj.sResultPtr(num));
            if ~temp || obj.sResult(num).MC06_Result(2)
                error('Error occured during %s\n temp=%d, sResult(%d).(2)=%d', FUNC_NAME, temp, num, obj.sResult(num).MC06_Result(2));
            end
        end
        function pData = BRDriveData(obj, num, number)
            %pData = BRDriveData(obj, num, number) reads the data from DRIVE DATA (number) PORT
            if nargin == 3
                switch number
                    case 1
                        FUNC_NAME = 'MC06_BRDriveData1';
                    case 2
                        FUNC_NAME = 'MC06_BRDriveData2';
                    case 3
                        FUNC_NAME = 'MC06_BRDriveData3';
                    otherwise
                        error('DrivePort Number has to be 1, 2, or 3')
                end
                pData = uint16(0);
                pDataPtr = libpointer('uint16Ptr', pData);
                [temp, pData, obj.sResult(num)] = calllib('Mc06A', FUNC_NAME, obj.hDev(num), pDataPtr, obj.sResultPtr(num));
                if ~temp || obj.sResult(num).MC06_Result(2)
                    error('Error occured during %s\n temp=%d, sResult(%d).(2)=%d', FUNC_NAME, temp, num, obj.sResult(num).MC06_Result(2));
                end
            else
               error('Wrong number of input arguments(BWDriveData)');
            end
        end
  
        %////// "設定関連(Drive parameters)"で使用 //////
        function L_DriveSet_LSPD(obj, num, LSPD)
            % L_DriveSet_LSPD(obj, num, LSPD) sets the L-shape Drive Parameter LSPD
            % LSPD : Start&End speed [Hz]
            if nargin~=3, error('Wrong number of input arguments') ; end
            obj.SetData1(num, LSPD);
            obj.Wait(num, 0);
            obj.IWDrive(num, '0010');
             %{   
            if num==0 || num==1 || num==2
                fprintf(' \nLSPD(Start&End speed) was changed to %.1f[Hz](= %.2f[mm/s])\n' ...
                        , LSPD, LSPD/obj.Degmm2Pulse(num));
            else
                fprintf(' \nLSPD(Start&End speed) was changed to %.1f[Hz](= %.2f[deg/s])\n' ...
                        , LSPD, LSPD/obj.Degmm2Pulse(num));
            end
            %}
        end
        function L_DriveSet_HSPD(obj, num, HSPD)
            % L_DriveSet_HSPD(obj, num, HSPD) sets the L-shape Drive Parameter HSPD
            % HSPD : Maximum speed [Hz]
            if nargin~=3, error('Wrong number of input arguments') ; end
            obj.SetData1(num, HSPD);
            obj.Wait(num, 0);
            obj.IWDrive(num, '0011');
            %{
            if num==0 || num==1 || num==2
                fprintf(' HSPD(maximum speed) was changed to %.1f[Hz](= %.2f[mm/s])\n' ...
                        , HSPD, HSPD/obj.Degmm2Pulse(num));
            else
                fprintf(' HSPD(maximum speed) was changed to %.1f[Hz](= %.2f[deg/s])\n' ...
                        , HSPD, HSPD/obj.Degmm2Pulse(num));
            end
            %}
        end
        function L_DriveSet_UDRATE(obj, num, URATE, DRATE)
            %L_DriveSet_UDRATE(obj, num, URATE,DRATE) sets the L-shape Drive Parameter URATE&DRATE
            %  URATE : start acceleration [ms/kHz]
            %  DRATE : end   acceleration [ms/kHz]
            %  The nearest value will be choosed from RATE_DATA[:]
            if nargin~=4, error('Wrong number of input arguments'); end

            [~, J1] = min( abs(obj.RATE_DATA - URATE) ); %URATEにいちばん近い値を配列RATE_DATAから検索
            URATE_CODE = num2str( dec2hex(J1) );         %要素番号をTABLE NO. (HEX CODE)にconvert
            while length(URATE_CODE)<2, URATE_CODE=strcat('0',URATE_CODE); end %無理やり0をつけて2桁にする

            [~, J2] = min( abs(obj.RATE_DATA - DRATE) ); %DRATEにいちばん近い値を配列RATE_DATAから検索
            DRATE_CODE = num2str( dec2hex(J2) );         %要素番号をTABLE NO. (HEX CODE)にconvert
            while length(DRATE_CODE)<2, DRATE_CODE=strcat('0',DRATE_CODE); end %無理やり0をつけて2桁にする

            S = strcat( URATE_CODE, DRATE_CODE ); %4桁の HEX_CODE作成
            obj.BWDriveData(num, 3, S);
            obj.Wait(num, 0);
            obj.BWDriveCommand(num, '0013');

            %{
            if num==0 || num==1 || num==2
                fprintf(' URATE(start acceleration) was changed to %.1f[ms/kHz](= %.2f[mm/s^2])\n' ...
                        ,obj.RATE_DATA(J1), 1e6/obj.RATE_DATA(J1)/obj.Degmm2Pulse(num));
                fprintf(' DRATE(end   acceleration) was changed to %.1f[ms/kHz](= %.2f[mm/s^2])\n' ...
                        ,obj.RATE_DATA(J2), 1e6/obj.RATE_DATA(J2)/obj.Degmm2Pulse(num));
            else
                fprintf(' URATE(start acceleration) was changed to %.1f[ms/kHz](= %.2f[deg/s^2])\n' ...
                        ,obj.RATE_DATA(J1), 1e6/obj.RATE_DATA(J1)/obj.Degmm2Pulse(num));
                fprintf(' DRATE(end   acceleration) was changed to %.1f[ms/kHz](= %.2f[deg/s^2])\n\n' ...
                        ,obj.RATE_DATA(J2), 1e6/obj.RATE_DATA(J2)/obj.Degmm2Pulse(num));
            end
            %}
        end
        function S_DriveSet_SLSPD(obj, num, SLSPD)
            % S_DriveSet_SLSPD(obj, num, SLSPD) sets the S-shape Drive Parameter SSPD
            % SLSPD : Start&End speed [Hz]
            if nargin~=3, error('Wrong number of input arguments') ; end

            obj.SetData1(num, SLSPD);
            obj.Wait(num, 0);
            obj.IWDrive(num, '0030');

            %{
            if num==0 || num==1 || num==2
                fprintf(' \nSLSPD(Start&End speed) was changed to %.1f[Hz](= %.2f[mm/s])\n' ...
                        , SLSPD, SLSPD/obj.Degmm2Pulse(num));
            else
                fprintf(' \nSLSPD(Start&End speed) was changed to %.1f[Hz](= %.2f[deg/s])\n' ...
                        , SLSPD, SLSPD/obj.Degmm2Pulse(num));
            end
            %}
        end
        function S_DriveSet_SHSPD(obj, num, SHSPD)
            % S_DriveSet_SHSPD(obj, num, SHSPD) sets the S-shape Drive Parameter SHSPD
            % SHSPD : Maximum speed [Hz]
            if nargin~=3, error('Wrong number of input arguments') ; end

            obj.SetData1(num, SHSPD);
            obj.Wait(num, 0);
            obj.IWDrive(num, '0031');
           %{
            if num==0 || num==1 || num==2
                fprintf(' SHSPD(maximum speed) was changed to %.1f[Hz](= %.2f[mm/s])\n' ...
                        , SHSPD, SHSPD/obj.Degmm2Pulse(num));
            else
                fprintf(' SHSPD(maximum speed) was changed to %.1f[Hz](= %.2f[deg/s])\n' ...
                        , SHSPD, SHSPD/obj.Degmm2Pulse(num));
            end
            %}
        end
        function S_DriveSet_SUDRATE(obj, num, SURATE, SDRATE)
            %S_DriveSet_SUDRATE(obj, num, SURATE, SDRATE) sets the S-shape Drive Parameter SURATE & SDRATE
            %   SURATE : start acceleration [ms/kHz]
            %   SDRATE : end   acceleration [ms/kHz]
            %   The nearest value will be choosed from RATE_DATA[:]
            if nargin~=4, error('Wrong number of input arguments'); end
            
            [~, J1] = min( abs(obj.RATE_DATA - SURATE) ); %URATEにいちばん近い値を配列RATE_DATAから検索
            SURATE_CODE = num2str( dec2hex(J1) );         %要素番号をTABLE NO. (HEX CODE)にconvert
            while length(SURATE_CODE)<2, SURATE_CODE=strcat('0', SURATE_CODE); end %無理やり0をつけて2桁にする

            [~, J2] = min( abs(obj.RATE_DATA - SDRATE) ); %DRATEにいちばん近い値を配列RATE_DATAから検索
            SDRATE_CODE = num2str( dec2hex(J2) );         %要素番号をTABLE NO. (HEX CODE)にconvert
            while length(SDRATE_CODE)<2, SDRATE_CODE=strcat('0', SDRATE_CODE); end %無理やり0をつけて2桁にする

            S = strcat( SURATE_CODE, SDRATE_CODE ); %4桁の HEX_CODE作成

            obj.BWDriveData(num, 3, S);
            obj.Wait(num, 0);
            obj.BWDriveCommand(num, '0033');
            %{
            if num==0 || num==1 || num==2
                fprintf(' SURATE(start acceleration) was changed to %.1f[ms/kHz](= %.2f[mm/s^2])\n' ...
                        ,obj.RATE_DATA(J1), 1e6/obj.RATE_DATA(J1)/obj.Degmm2Pulse(num));
                fprintf(' SDRATE(end   acceleration) was changed to %.1f[ms/kHz](= %.2f[mm/s^2])\n' ...
                        ,obj.RATE_DATA(J2), 1e6/obj.RATE_DATA(J2)/obj.Degmm2Pulse(num));
            else
                fprintf(' SURATE(start acceleration) was changed to %.1f[ms/kHz](= %.2f[deg/s^2])\n' ...
                        ,obj.RATE_DATA(J1), 1e6/obj.RATE_DATA(J1)/obj.Degmm2Pulse(num));
                fprintf(' SDRATE(end   acceleration) was changed to %.1f[ms/kHz](= %.2f[deg/s^2])\n\n' ...
                        ,obj.RATE_DATA(J2), 1e6/obj.RATE_DATA(J2)/obj.Degmm2Pulse(num));
            end
            %}
        end
        function S_DriveSet_SCAREA12(obj, num, SCAREA1, SCAREA2)
            % S_DriveSet_SCAREA12(obj, num, SCAREA1, SCAREA2) sets the S-shape Drive Parameter SCAREA12
            %   SCAREA1 : start of 1st S-shape [Hz]
            %   SCAREA2 : end   of 1st S-shape [Hz]
            if nargin~=4, error('Wrong number of input arguments') ; end

            HEX_DATA1 = dec2hex( SCAREA1/50 );
            HEX_DATA2 = dec2hex( SCAREA2/50 );
            obj.BWDriveData(num, 2, HEX_DATA2); %SCAREA2 SET
            obj.BWDriveData(num, 3, HEX_DATA1); %SCAREA1 SET
            obj.Wait(num, 0);
            obj.BWDriveCommand(num, '0034');
            %{
            if num==0 || num==1 || num==2
                fprintf(' SCAREA1(s-shape speed) was changed to %.1f[Hz](= %.2f[mm/s])\n' ...
                        , SCAREA1, SCAREA1/obj.Degmm2Pulse(num));
                fprintf(' SCAREA2(s-shape speed) was changed to %.1f[Hz](= %.2f[mm/s])\n' ...
                        , SCAREA2, SCAREA2/obj.Degmm2Pulse(num));
             else
                fprintf(' SCAREA1(s-shape speed) was changed to %.1f[Hz](= %.2f[deg/s])\n' ...
                        , SCAREA1, SCAREA1/obj.Degmm2Pulse(num));
                fprintf(' SCAREA2(s-shape speed) was changed to %.1f[Hz](= %.2f[deg/s])\n' ...
                        , SCAREA2, SCAREA2/obj.Degmm2Pulse(num));
            end
            %}
        end
        function S_DriveSet_SCAREA34(obj, num, SCAREA3, SCAREA4)
            % S_DriveSet_SCAREA34(obj, num, SCAREA3, SCAREA4) sets the S-shape Drive Parameter SCAREA43
            %   SCAREA3 : start of 2nd S-shape [Hz]
            %   SCAREA4 : end   of 2nd S-shape [Hz]
            if nargin~=4, error('Wrong number of input arguments') ; end

            HEX_DATA3 = dec2hex( SCAREA3/50 );
            HEX_DATA4 = dec2hex( SCAREA4/50 );
            obj.BWDriveData(num, 2, HEX_DATA3); %SCAREA3 SET
            obj.BWDriveData(num, 3, HEX_DATA4); %SCAREA4 SET
            obj.Wait(num, 0);
            obj.BWDriveCommand(num, '0035');
            %{
            if num==0 || num==1 || num==2
                fprintf(' SCAREA3(s-shape speed) was changed to %.1f[Hz](= %.2f[mm/s])\n' ...
                        , SCAREA3, SCAREA3/obj.Degmm2Pulse(num));
                fprintf(' SCAREA4(s-shape speed) was changed to %.1f[Hz](= %.2f[mm/s])\n' ...
                        , SCAREA4, SCAREA4/obj.Degmm2Pulse(num));
             else
                fprintf(' SCAREA3(s-shape speed) was changed to %.1f[Hz](= %.2f[deg/s])\n' ...
                        , SCAREA3, SCAREA3/obj.Degmm2Pulse(num));
                fprintf(' SCAREA4(s-shape speed) was changed to %.1f[Hz](= %.2f[deg/s])\n' ...
                        , SCAREA4, SCAREA4/obj.Degmm2Pulse(num));
            end
            %}
        end
        
        %////// "Drive speed parameter を設定 //////
        function L_SetDrivePara(obj, num, StartEnd_Vel, Max_Vel, Accel_1, Accel_2)
            % L_SetDrivePara(obj, num, StartEnd_Vel, Max_Vel, Accel_1, Accel_2) sets the L-shape Drive Parameters
            %   StartEnd_Vel : Start&End speed [mm/s] for X,Y,Z or [deg/s] for R,A
            %   Max_Vel      : MAximum speed [mm/s] for X,Y,Z or [deg/s] for R,A
            %   Accel_1&2    : Start&End Acceleration [mm/s^2] for X,Y,Z or [deg/s^2] for R,A
            %   if any argument<=0, the corresponding setting will not be performed.
            if nargin~=6, error('Wrong number of input arguments'); end

            % Setting of StartEnd_Vel
            if StartEnd_Vel>obj.Vel_Max(num)
                fprintf( 'StartEnd_Vel is too big. Maximum limit=%d\n', obj.Vel_Max(num) ) ;
                fprintf( 'Setting of StartEnd_Vel is cancelled\n' );
            elseif StartEnd_Vel<=0
                fprintf( 'Setting of StartEnd_Vel is not performed\n' );
            else
                LSPD = StartEnd_Vel*obj.Degmm2Pulse(num);   %convert to [Hz: Pulse/s]
                obj.L_DriveSet_LSPD(num, LSPD);             %LSPD SET
            end
            
            % Setting of Max_Vel
            if Max_Vel>obj.Vel_Max(num)
                fprintf( 'Max_Vel is too big. Maximum limit=%d\n', obj.Vel_Max(num) );
                fprintf( 'Setting of Max_Vel is cancelled\n' );
            elseif Max_Vel<=0
                fprintf( 'Setting of Max_Vel is not performed\n' );
            else
                HSPD = Max_Vel*obj.Degmm2Pulse(num);   %convert to [Hz: Pulse/s]
                obj.L_DriveSet_HSPD(num, HSPD);             %HSPD SET
            end
            % Setting of Accel_1&2
            if Accel_1>obj.Accel_Max(num) || Accel_2>obj.Accel_Max(num)
                fprintf( 'Accel_1 or 2 is too big. Maximum limit=%d\n', obj.Accel_Max(num) );
                fprintf( 'Setting of Accel_1 & 2 is cancelled\n' );
            elseif Accel_1<=0 && Accel_2<=0;
                fprintf( 'Setting of Accel_1 & 2 is not performed\n' );
            else
                if Accel_1<=0 %どちらかが0のときは他方と同じにする。(バグ回避)
                    DRATE = 1e6/( Accel_2*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
                    URATE = DRATE;    
                elseif Accel_2<=0
                    URATE = 1e6/( Accel_1*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
                    DRATE = URATE;
                else
                    URATE = 1e6/( Accel_1*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
                    DRATE = 1e6/( Accel_2*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
                end
                obj.L_DriveSet_UDRATE(num, URATE, DRATE); %URATE&DRATE SET
            end
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
            if nargin~=10, error('Wrong number of input arguments') ; end
            
            % Setting of StartEnd_Vel
            if StartEnd_Vel>obj.Vel_Max(num)
                fprintf( 'StartEnd_Vel is too big. Maximum limit=%d\n', obj.Vel_Max(num) ) ;
                fprintf( 'Setting of StartEnd_Vel is cancelled\n' );
            elseif StartEnd_Vel<=0
                fprintf( 'Setting of StartEnd_Vel is not performed\n' );
            else
                SLSPD = StartEnd_Vel*obj.Degmm2Pulse(num);  %convert to [Hz: Pulse/s]
                obj.S_DriveSet_SLSPD(num, SLSPD);           %SLSPD SET
            end
            
            % Setting of Max_Vel
            if Max_Vel>obj.Vel_Max(num)
                fprintf( 'Max_Vel is too big. Maximum limit=%d\n', obj.Vel_Max(num) );
                fprintf( 'Setting of Max_Vel is cancelled\n' );
            elseif Max_Vel<=0
                fprintf( 'Setting of Max_Vel is not performed\n' );
            else
                SHSPD = Max_Vel*obj.Degmm2Pulse(num);        %convert to [Hz: Pulse/s]
                obj.S_DriveSet_SHSPD(num, SHSPD);            %SHSPD SET
            end

            % Setting of Accel_1&2
            if Accel_1>obj.Accel_Max(num) || Accel_2>obj.Accel_Max(num)
                fprintf( 'Accel_1 or 2 is too big. Maximum limit=%d\n', obj.Accel_Max(num) );
                fprintf( 'Setting of Accel_1&2is cancelled\n' );
            elseif Accel_1<=0 && Accel_2<=0;
                fprintf( 'Setting of Accel_1&2 is not performed\n' );
            else
                if Accel_1<=0 %どちらかが0のときは他方と同じにする。(バグ回避)
                    SDRATE = 1e6/( Accel_2*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
                    SURATE = SDRATE;    
                elseif Accel_2<=0
                    SURATE = 1e6/( Accel_1*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
                    SDRATE = SURATE;
                else
                    SURATE = 1e6/( Accel_1*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
                    SDRATE = 1e6/( Accel_2*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
                end
                obj.S_DriveSet_SUDRATE(num, SURATE, SDRATE); %SURATE & SDRATE SET
            end

             % Setting of S字部分の速度最初の2箇所(SCAREA1 & SCAREA2)
            if S_Vel1>obj.Vel_Max(num) || S_Vel2>obj.Vel_Max(num)
                fprintf( 'S_Vel 1 or 2 is too big. Maximum limit=%d\n', obj.Vel_Max(num) );
                fprintf( 'Setting of SCAREA_1 & 2 is cancelled\n' );
            elseif S_Vel1<=0 && S_Vel2<=0;
                fprintf( 'Setting of SCAREA_1 & 2 is not performed\n' );
            else
                if S_Vel1<=0 %どちらかが0のときは他方と同じにする。(バグ回避)
                    SCAREA2 = 1e6/( S_Vel2*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
                    SCAREA1 = SCAREA2;
                elseif S_Vel2<=0
                    SCAREA1 = 1e6/( S_Vel1*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
                    SCAREA2 = SCAREA1;
                else
                    SCAREA1 = 1e6/( S_Vel1*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
                    SCAREA2 = 1e6/( S_Vel2*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
                end
                obj.S_DriveSet_SCAREA12(num, SCAREA1, SCAREA2); %SCAREA1 & SCAREA2 SET
            end           

             % Setting of S字部分の速度最初の2箇所(SCAREA3 & SCAREA4)
            if S_Vel3>obj.Vel_Max(num) || S_Vel4>obj.Vel_Max(num)
                fprintf( 'S_Vel 3 or 4 is too big. Maximum limit=%d\n', obj.Vel_Max(num) );
                fprintf( 'Setting of SCAREA_3 & 4 is cancelled\n' );
            elseif S_Vel3<=0 && S_Vel4<=0;
                fprintf( 'Setting of SCAREA_3 & 4 is not performed\n' );
            else
                if S_Vel3<=0 %どちらかが0のときは他方と同じにする。(バグ回避)
                    SCAREA4 = 1e6/( S_Vel4*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
                    SCAREA3 = SCAREA4;
                elseif S_Vel4<=0
                    SCAREA3 = 1e6/( S_Vel3*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
                    SCAREA4 = SCAREA3;
                else
                    SCAREA3 = 1e6/( S_Vel3*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
                    SCAREA4 = 1e6/( S_Vel4*obj.Degmm2Pulse(num) ); %convert to [ms/kHz]
                end
                obj.S_DriveSet_SCAREA34(num, SCAREA3, SCAREA4); %SCAREA3 & SCAREA4 SET
            end           
        end
        %////// "Drive speedを 低.中.高 の3段階で設定"で使用//////
        function L_SetDriveSpeed(obj, num, Speed)
            % L_SetDriveSpeed(obj, num, Speed) sets the L-shape Drive speed
            % Speed: 'slow', 'medium', 'fast'
            if nargin~=3, error('Wrong number of input arguments') ; end

            switch lower(Speed)
                case 'slow'  % Max_Vel以外は初期値を使用
                    obj.L_SetDrivePara(num, obj.Ini_Ldrive_data(num,1), obj.Vel_3level(num,1), obj.Ini_Ldrive_data(num,3), obj.Ini_Ldrive_data(num,4));
        %            fprintf( ' ''L'' Drive %d Speed is set to ''slow''\n',num );
                case 'medium'
                    obj.L_SetDrivePara(num, obj.Ini_Ldrive_data(num,1), obj.Vel_3level(num,2), obj.Ini_Ldrive_data(num,3), obj.Ini_Ldrive_data(num,4));
        %            fprintf( ' ''L'' Drive %d Speed is set to ''medium''\n',num );
                case 'fast'
                    obj.L_SetDrivePara(num, obj.Ini_Ldrive_data(num,1), obj.Vel_3level(num,3), obj.Ini_Ldrive_data(num,3), obj.Ini_Ldrive_data(num,4));
        %            fprintf( ' ''L'' Drive %d Speed is set to ''fast''\n',num );
                otherwise
                    fprintf( ' ''Speed'' has to be ''slow'', ''medium'', or ''fast''\n' );
                    fprintf( 'L_SetDriveSpeed is cancelled\n' );
            end
        end
        function S_SetDriveSpeed(obj, num, Speed)
            % S_SetDriveSpeed(obj, num, Speed) sets the S-shape Drive speed
            % Speed: 'slow', 'medium', 'fast'
            if nargin~=3, error('Wrong number of input arguments') ; end

            switch lower(Speed)
                case 'slow'  % Max_Vel以外は初期値を使用
                    %obj.S_SetDrivePara(num, obj.Ini_Sdrive_data(num,1), obj.Vel_3level(num,1), obj.Ini_Sdrive_data(num,3:8));
                    obj.S_SetDrivePara( num, obj.Ini_Sdrive_data(num,1), obj.Vel_3level(num,1), obj.Ini_Sdrive_data(num,3), ...
                                            obj.Ini_Sdrive_data(num,4), obj.Ini_Sdrive_data(num,5), obj.Ini_Sdrive_data(num,6), ...
                                            obj.Ini_Sdrive_data(num,7), obj.Ini_Sdrive_data(num,8) );
         %           fprintf( ' ''S'' Drive %d Speed is set to ''slow''\n',num );
                case 'medium'
                    obj.S_SetDrivePara(num, obj.Ini_Sdrive_data(num,1), obj.Vel_3level(num,2), obj.Ini_Sdrive_data(num,3), ...
                                            obj.Ini_Sdrive_data(num,4), obj.Ini_Sdrive_data(num,5), obj.Ini_Sdrive_data(num,6), ...
                                            obj.Ini_Sdrive_data(num,7), obj.Ini_Sdrive_data(num,8) );
         %           fprintf( ' ''S'' Drive %d Speed is set to ''medium''\n',num );
                case 'fast'
                    obj.S_SetDrivePara(num, obj.Ini_Sdrive_data(num,1), obj.Vel_3level(num,3), obj.Ini_Sdrive_data(num,3), ...
                                            obj.Ini_Sdrive_data(num,4), obj.Ini_Sdrive_data(num,5), obj.Ini_Sdrive_data(num,6), ...
                                            obj.Ini_Sdrive_data(num,7), obj.Ini_Sdrive_data(num,8) );
         %           fprintf( ' ''S'' Drive %d Speed is set to ''fast''\n',num );
                otherwise
                    fprintf( '''Speed'' has to be ''slow'', ''medium'', or ''fast''\n' );
                    fprintf( 'S_SetDriveSpeed is cancelled\n' );
            end
        end

        %////// 各種データの読み出しで使用 //////
        function LDriveParameter(obj, num)
            %LDriveParameter(obj, num) outputs the current L Drive Parameters
            fprintf( '\n///// Parameters for Linear Drive /////\n' );
            obj.DataRead(num, '0010'); %LSPD SET
            fprintf(' LSPD(Start Pulse Speed) = %d[Hz]\n', obj.GetData(num));
            obj.DataRead(num, '0011'); %HSPD SET
            fprintf(' HSPD(Maximum Pulse Speed) = %d[Hz]\n', obj.GetData(num));
            obj.DataRead(num, '0013'); %RATE SET
            S = num2str( dec2hex( obj.sData(num).MC06_Data(3) ) );
            while length(S)<4, S=strcat('0',S); end %無理やり0をつけて4桁にする
          % fprintf(' URATE(start acceleration): Table NO. %s\n', S(1:2));
          % fprintf(' DRATE(end   acceleration): Table NO. %s\n', S(3:4));
            fprintf(' URATE(start acceleration): %d[ms/kHz]\n',obj.RATE_DATA_TABLE(S(1:2)));
            fprintf(' DRATE(end   acceleration): %d[ms/kHz]\n',obj.RATE_DATA_TABLE(S(3:4)));
        end
        function SDriveParameter(obj, num)
            %SDriveParameter(obj, num) outputs the current SDrive Parameters
            fprintf( '\n///// Parameters for S-shape Drive /////\n' );
            obj.DataRead(num, '0030'); %SLSPD SET
            fprintf(' SLSPD(Start Pulse Speed) = %d[Hz]\n', obj.GetData(num));
            obj.DataRead(num, '0031'); %SHSPD SET
            fprintf(' SHSPD(Maximum Pulse Speed) = %d[Hz]\n', obj.GetData(num));
            obj.DataRead(num, '0033'); %SRATE SET
            S = num2str( dec2hex( obj.sData(num).MC06_Data(3) ) );
            while length(S)<4, S=strcat('0',S); end %無理やり0をつけて4桁にする
           %fprintf(' SURATE(start acceleration): Table NO. %s\n', S(1:2));
           %fprintf(' SDRATE(end   acceleration): Table NO. %s\n', S(3:4));
            fprintf(' SURATE(start acceleration): %d[ms/kHz]\n',obj.RATE_DATA_TABLE(S(1:2)));
            fprintf(' SDRATE(end   acceleration): %d[ms/kHz]\n',obj.RATE_DATA_TABLE(S(3:4)));
            obj.DataRead(num, '0034'); %SCAREA12 SET
            fprintf(' SCAREA1 = %d[Hz]\n', obj.sData(num).MC06_Data(3)*50);
            fprintf(' SCAREA2 = %d[Hz]\n', obj.sData(num).MC06_Data(2)*50);
            obj.DataRead('0035'); %SCAREA34 SET
            fprintf(' SCAREA3 = %d[Hz]\n', obj.sData(num).MC06_Data(2)*50);
            fprintf(' SCAREA4 = %d[Hz]\n', obj.sData(num).MC06_Data(3)*50);
        end   
        function DataRead(obj, num, HEX_CODE)
            %DataRead(obj, num, HEX_CODE) reads the data on DRIVE DATA PORT
            %取説(コマンド編) P.72参照
            obj.Wait(num, 0);
            obj.BWDriveData(num, 3, HEX_CODE); %Command code(LSPD SET)
            obj.BWDriveCommand(num, '0089'); %HEX CODE (SET DATA READ)
            obj.Wait(num, 0);
            obj.BWDriveCommand(num, 'F041'); %HEX CODE (DATA READ PORT SELECT)
            obj.IRDrive(num);
%           obj.sData.MC06_Data
%           pData = obj.GetData
        end
        function Rate = RATE_DATA_TABLE(obj, Table_number)
            %取説 P.49(4)参照
            if nargin~=2, error('Wrong number of input arguments') ; end
            if hex2dec(Table_number)>60
                error('Table_number has to be 00~3C');
            elseif hex2dec(Table_number)==0
                Rate = 1000; %RATE_DATA配列は要素番号0を持てないのでこれだけ例外で考える.
            else
                Rate = obj.RATE_DATA( hex2dec(Table_number) );
            end
        end
        
        %////// SCAN DRIVE /////
        function Jog_minus(obj, num)
            % Jog_minus(obj, num) excutes -JOG Drive (only 1 pulse)
            if nargin~=2, error('Wrong number of input arguments') ; end
            obj.Wait(num, 0);
            obj.BWDriveCommand(num, '0020');
        end
        function Jog_plus(obj, num)
            % Jog_plus(obj, num) excutes +JOG Drive (only 1 pulse)
            if nargin~=2, error('Wrong number of input arguments') ; end
            obj.Wait(num, 0);
            obj.BWDriveCommand(num, '0021');
        end        
        function L_Scan_minus(obj, num)
            % L_Scan_minus(obj, num) excutes - L-shaped SCAN
            %   This is the endless drive, so you have to stop the drive by yourself.
            if nargin~=2, error('Wrong number of input arguments') ; end
            obj.Wait(num, 0);
            obj.BWDriveCommand(num, '0022');
        end        
        function L_Scan_plus(obj, num)
            % L_Scan_plus(obj, num) excutes + L-shaped SCAN
            %   This is the endless drive, so you have to stop the drive by yourself.
            if nargin~=2, error('Wrong number of input arguments') ; end
            obj.Wait(num, 0);
            obj.BWDriveCommand(num, '0023');
        end
        function L_IncDrive(obj, num, Degmm)
            %L_IncDrive(obj, num, Degmm) excutes the relative L-shaped drive
            %   Degmm : degree or mm
            if nargin~=3, error('Wrong number of input arguments') ; end
            if abs(Degmm)>obj.Move_Limit(num), error('Movement %d is too big: ',Degmm); end %事故防止:移動量はMove_Limit以内に限定

            pulse_num = uint32( abs(Degmm)*obj.Degmm2Pulse(num) ); %Number of pulses
            if Degmm>0  %Scan装置記載の符号と整合させるためわざと逆転させている
                pulse_num = bitcmp( pulse_num, 'uint32' ); %負数は2の補数で与える
            end
            
            obj.SetData1(num, pulse_num);
            obj.Wait(num, 0);
            obj.IWDrive(num, '0024');
        end        
        function L_AbsDrive(obj, num, Degmm)
            %L_AbsDrive(obj, num, Degmm) excutes the absolute L-shaped drive
            %   Degmm : degree or mm
            if nargin~=3, error('Wrong number of input arguments') ; end
            if abs(Degmm)>obj.Move_Limit(num), error('Movement %d is too big: ',Degmm); end %事故防止:移動量はMove_Limit以内に限定

            pulse_num = uint32( abs(Degmm)*obj.Degmm2Pulse(num) ); %Number of pulses
            if Degmm>0
                pulse_num = bitcmp( pulse_num, 'uint32' ); %負数は2の補数で与える
            end
            
            obj.SetData1(num, pulse_num);
            obj.Wait(num, 0);
            obj.IWDrive(num, '0025');
        end
        function S_Scan_minus(obj, num)
            % S_Scan_minus(obj, num) excutes - S-shaped SCAN
            %   This is the endless drive, so you have to stop the drive by yourself.
            if nargin~=2, error('Wrong number of input arguments') ; end
            obj.Wait(num, 0);
            obj.BWDriveCommand(num, '0042');
        end        
        function S_Scan_plus(obj, num)
            % S_Scan_plus(obj, num) excutes + S-shaped SCAN
            %   This is the endless drive, so you have to stop the drive by yourself.
            if nargin~=2, error('Wrong number of input arguments') ; end
            obj.Wait(num, 0);
            obj.BWDriveCommand(num, '0043');
        end        
        function S_IncDrive(obj, num, Degmm)
            %S_IncDrive(obj, num, Degmm) excutes the relative S-shaped drive
            %   Degmm : degree or mm
            if nargin~=3, error('Wrong number of input arguments') ; end
            if abs(Degmm)>obj.Move_Limit(num), error('Movement %d is too big: ',Degmm); end %事故防止:移動量はMove_Limit以内に限定

            pulse_num = uint32( abs(Degmm)*obj.Degmm2Pulse(num) ); %Number of pulses
            if Degmm>0  %Scan装置記載の符号と整合させるためわざと逆転させている
                pulse_num = bitcmp( pulse_num, 'uint32' ); %負数は2の補数で与える
            end
            
            obj.SetData1(num, pulse_num);
            obj.Wait(num, 0);
            obj.IWDrive(num, '0044');
        end        
        function S_AbsDrive(obj, num, Degmm)
            %S_AbsDrive(obj, num, Degmm) excutes the absolute S-shaped drive
            %   Degmm : degree or mm
            if nargin~=3, error('Wrong number of input arguments') ; end
            if abs(Degmm)>obj.Move_Limit(num), error('Movement %d is too big: ',Degmm); end %事故防止:移動量はMove_Limit以内に限定

            pulse_num = uint32( abs(Degmm)*obj.Degmm2Pulse(num) ); %Number of pulses
            if Degmm>0
                pulse_num = bitcmp( pulse_num, 'uint32' ); %負数は2の補数で与える
            end
            
            obj.SetData1(num, pulse_num);
            obj.Wait(num, 0);
            obj.IWDrive(num, '0045');
        end    
    end       
end %class



