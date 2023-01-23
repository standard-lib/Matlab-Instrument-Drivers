clear all
PS = MID_CV87x();

%PS.resetAddress('XYZR');

% PS.setSpeed('Slow', 'XYZR');
% PS.driveAbs('X',30, 'Y', 30, 'Z', 5,'R', 30);
PS.queryAddress()
% PS.setSpeed('Fast', 'XYZR');
% PS.driveAbs('X', 0, 'Y',  0, 'Z', 0,'R', 0);
PS.driveAbs('X', 0, 'Y',  0, 'Z', -100,'R', 0);
PS.queryAddress()
clear PS