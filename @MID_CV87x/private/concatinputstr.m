function [concatenatedstr] = concatinputstr(celllist)
%CONCATINPUTSTR concatenate strings in cell
%   concatenate strings in cell
    concatenatedstr = '';
    for i = 1:numel(celllist) 
        concatenatedstr = strcat(concatenatedstr, celllist{i});
    end
end

