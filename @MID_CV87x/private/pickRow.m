function [cellvect] = pickRow(M, rowName, readCols)
%PICKROW pick cell's row from rowName
    row = find(strcmpi(rowName,M(:,1)),1);
    cellvect = M(row, readCols);
end

