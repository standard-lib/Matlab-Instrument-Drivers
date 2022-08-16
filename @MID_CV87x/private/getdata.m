function [value32] = getdata(arraydata, type)
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
    value32 = typecast( [arraydata(3), arraydata(2)], type );
end
