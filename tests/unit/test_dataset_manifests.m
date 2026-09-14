function tests = test_dataset_manifests
%TEST_DATASET_MANIFESTS  Unit tests for the dataset layer (loadDataset,
%buildDatasetManifests, validateDataset).
    tests = functiontests(localfunctions);
end

function test_loadDatasetAllKnownNames(testCase)
    names = {'aptos', 'idrid', 'drive', 'messidor2'};
    for i = 1:numel(names)
        ds = loadDataset(names{i});
        verifyTrue(testCase, isfield(ds, 'status'));
        verifyTrue(testCase, isfield(ds, 'files'));
        verifyTrue(testCase, isfield(ds, 'split'));
        verifyFalse(testCase, isempty(ds.status));
    end
end

function test_loadDatasetUnknownRaises(testCase)
    err = @() loadDataset('nonsense');
    verifyError(testCase, err, 'RetinaSense:loadDataset:UnknownDataset');
end

function test_loadDatasetDirectoryActuallyExists(testCase)
    ds = loadDataset('aptos');
    if ~strcmp(ds.status, 'NOT AVAILABLE')
        for i = 1:min(4, ds.n)
            verifyTrue(testCase, exist(ds.files(i), 'file') == 2);
        end
    end
end

function test_validateDatasetBounded(testCase)
    r = validateDataset('aptos', 4);
    verifyLessThanOrEqual(testCase, r.nSampled, 5);   % bounded sample check
    if strcmp(r.status, 'PASS')
        verifyTrue(testCase, isempty(r.errors));
    end
end

function test_messidor2ExternalOnly(testCase)
    ds = loadDataset('messidor2');
    if ds.n > 0
        verifyTrue(testCase, all(ds.split == "external"));  % NEVER train/val
    end
end