clear rpr
% make handler
rpr = MID_RPR4000('Prolific'); % default:safemode = true, debugmode = false
rpr.setRepRate(100);
repRate = rpr.queryRepRate()
rpr.setFrequencyAndCycle(1e6,9);
freq = rpr.queryFrequency()
cycle = rpr.queryCycle()
rpr.setControl(0);
control = rpr.queryControl()
rpr.setTrigger('EXT');
trigger = rpr.queryTrigger();

rpr.setFrequency(2e6);
freq = rpr.queryFrequency()
rpr.setCycle(5);
cycle = rpr.queryCycle()
rpr.setControl(0);
control = rpr.queryControl()
rpr.setRepRate(50.0);
repRate = rpr.queryRepRate()
rpr.setTrigger('INT');
trigger = rpr.queryTrigger();
clear rpr
