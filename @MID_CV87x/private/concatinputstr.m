function [concatenatedstr] = concatinputstr(celllist)
%UNTITLED この関数の概要をここに記述
%   詳細説明をここに記述
    concatenatedstr = '';
    for i = 1:numel(celllist) 
        concatenatedstr = strcat(concatenatedstr, celllist{i});
    end
end

