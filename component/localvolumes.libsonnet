local com = import 'lib/commodore.libjsonnet';
local espejo = import 'lib/espejo.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_local_storage;

local LocalVolume(name, volspec) =
  kube._Object('local.storage.openshift.io/v1', 'LocalVolume', name)
  {
    metadata+: {
      annotations+: {
        'argocd.argoproj.io/sync-options': 'SkipDryRunOnMissingResource=true',
      },
      namespace: params.namespace,
    },
    spec:
      com.makeMergeable(volspec.config) +
      {
        storageClassDevices: [
          volspec.storage_class_devices[sc] {
            storageClassName: sc,
          }
          for sc in std.objectFields(volspec.storage_class_devices)
        ],
      },
  };

local volumes = [
  LocalVolume(vn, params.local_volumes[vn])
  for vn in std.objectFields(params.local_volumes)
];

{
  localvolumes: volumes,
}
