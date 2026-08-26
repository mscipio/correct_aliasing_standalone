function tests = testDicomRouting
%TESTDICOMROUTING [REPLACED by testConverterBoundary.m in T003]
%   This file is retained as a placeholder. All converter-boundary tests
%   have been moved to testConverterBoundary.m, which uses a contract-shaped
%   fake dicom2nifti.api.run facade.

tests = functiontests(localfunctions);
end

function testReplacedByConverterBoundary(testCase)
% Placeholder test confirming the migration from testDicomRouting to
% testConverterBoundary. The old extension-dispatch tests are no longer
% relevant — T003 replaced all routing with a single converter path.
testCase.verifyTrue(true, 'Replaced by testConverterBoundary');
end
