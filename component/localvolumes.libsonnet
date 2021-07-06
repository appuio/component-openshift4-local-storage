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

local buildLabelSelector(volspec) =
  local restrictions = volspec.restricted_to;
  {
    matchExpressions: [
      local e = restrictions[k];
      local hasval = std.objectHas(e, 'values');
      // Invert given restrictions, since we want to deploy the
      // ResourceQuota in all namespaces which shouldn't use the
      // storageclass.
      local op = if hasval then 'NotIn' else 'DoesNotExist';
      {
        key: k,
        operator: op,
        [if hasval then 'values']: e.values,
      }
      for k in std.objectFields(restrictions)
    ],
  };

local syncconfigs = std.prune([
  local volspec = params.local_volumes[vn];
  if std.objectHas(volspec, 'restricted_to') then
    local name = 'openshift4-local-storage-restrict-%s' % vn;
    espejo.syncConfig(name) {
      spec: {
        forceRecreate: true,
        namespaceSelector: {
          labelSelector: buildLabelSelector(volspec),
        },
        syncItems: [
          {
            apiVersion: 'v1',
            kind: 'ResourceQuota',
            metadata: {
              name: name,
              labels: {
                'app.kubernetes.io/part-of': 'openshift4-local-storage',
              },
            },
            spec: {
              hard: {
                ['%s.storageclass.storage.k8s.io/persistentvolumeclaims' % sc]: '0'
                for sc in std.objectFields(volspec.storage_class_devices)
              },
            },
          },
        ],
      },
    }
  else null
  for vn in std.objectFields(params.local_volumes)
]);

{
  localvolumes: volumes,
  restriction_syncconfigs: syncconfigs,
}
