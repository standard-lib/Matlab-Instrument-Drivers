function [arraydata] = setdata_two8(indataMSB, indataLSB)
arguments
    indataMSB {int32,int16,int8}
    indataLSB {int32,int16,int8}
end
%SETDATA_TWO8 Pack two variable (the lower 8 bits) to one 16 bit variable.
    msb8 = bitand(int32(0x000000ff), int32(indataMSB)); % msb8 is int32
    lsb8 = bitand(int32(0x000000ff), int32(indataLSB)); % lsb8 is int32
    arraydata = zeros(3,1, 'uint16');
    arraydata(3) = bitor( bitshift(msb8,8), lsb8 );
end
