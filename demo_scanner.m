clear all
PS = MID_CV87x();

PS.resetAddress('XYZR');

PS.setSpeed('Slow', 'XYZR');
PS.driveAbs('X',-30, 'Y', -30, 'Z', 30,'R', 30);

PS.setSpeed('Fast', 'XYZR');
PS.driveAbs('X', 30, 'Y',  30, 'Z', -30,'R', -30);

