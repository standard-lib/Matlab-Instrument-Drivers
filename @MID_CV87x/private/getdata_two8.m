function [valMSB, valLSB] = getdata_two8(arraydata, type)
%GETDATA concatate data2 port and data3 port
% usage :
% >> getdata(arraydata, 'uint32')
% bit列はuint32として返される
% >> getdata(arraydata, 'int32')
% bit列は符号付きのint32として解釈されて返される
    arguments
        arraydata uint16
        type char
    end
    val = typecast(arraydata(3), type);
    valMSB = val(2);
    valLSB = val(1);
end
