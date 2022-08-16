function assertin(value, minimum, maximum)
%ASSERTIN assertion for the value is in the range
%  assertion for the "value" is in the range ["minimum", "maximum"]
    assert( minimum <= maximum, 'the range for assertion is invalid (minimum > maximum)');
    assert( all( minimum <= value ) && all(maximum >= value ), 'the value(s) is not in [%e, %e]', minimum, maximum ); 
end

