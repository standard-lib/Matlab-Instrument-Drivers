clear all
% PS = MID_OptoSigma("COM7", 'controllerPartNumber', 'SHOT-702', 'stagePartNumber', 'OSMS26-200(Z)-G10', 'debugmode', true);
% PS = MID_OptoSigma("COM7", controllerName = "SHOT-702", stageNames = "OSMS26-200(Z)-G10", debugmode = true);
PS = MID_OptoSigma("USB\VID_067B&PID_2303\5&2ED43146&0&3", controllerName = "SHOT-702", stageNames = "OSMS26-200(Z)-G10");
PS.driveAbs(1,1.0,acc=0.1); %最大加速度0.1mm/s^2で移動
PS.driveAbs(1,0.0);

PS.waitForSend();
