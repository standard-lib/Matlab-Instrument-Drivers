function [arraydata] = setdata1_32(int32data)
arguments
    int32data int32
end
%SETDATA1_24 Deomposes the upper 8 and lower 16 bits of a 24-bit int32 type
%number and puts them into uint16 array.
    arr = typecast( int32data , 'uint16');
    arraydata = zeros(3,1, 'uint16');
    arraydata(2) = arr(2);
    arraydata(3) = arr(1);
end

