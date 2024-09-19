clear all
% PS = MID_OptoSigma("COM7", controllerName = "SHOT-702", stageNames = "OSMS26-200(Z)-G10", debugmode = true);
% PS = MID_OptoSigma("Prolific", controllerName = "SHOT-702", stageNames = ["OSMS20-85(X)","OSMS20-85(X)"]);
PS = MID_OptoSigma("COM11", controllerName = "SHOT-702", stageNames = ["OSMS20-85(X)","OSMS20-85(X)"], debugmode = true);
% PS = MID_OptoSigma("COM8", controllerName = "GIP-101B", stageNames = ["HPS60-20X-M5"]);
% PS.driveAbs(1,1.0,acc=0.1); %最大加速度0.1mm/s^2で移動
PS.driveAbs([1, 2], [1, -1],acc=0.1); %最大加速度0.1mm/s^2で移動
PS.queryAddress()
PS.driveAbs(1,0.0);
PS.queryAddress()
PS.driveAbs(2,0.0);
PS.queryAddress()
% PS.wait(); %軸が止まるまで待つ．version 0.1以降では，driveAbsは軸が止まるまで帰ってこないので不要
