axis_no = (1:8)';
Enable = [true; true; true; true; false; false; false; false];
Unit = {'mm'; 'mm'; 'deg'; 'mm'; 'mm'; 'mm'; 'mm'; 'mm'};

T = table(Enable, Unit, 'Rownames', axis_no);

