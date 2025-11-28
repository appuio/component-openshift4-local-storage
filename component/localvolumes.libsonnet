local com = import 'lib/commodore.libjsonnet';
local esp = import 'lib/espejote.libsonnet';
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

local metadataPatch = {
  annotations+: {
    'syn.tools/source': 'https://github.com/appuio/component-openshift4-local-storage.git',
  },
  labels+: {
    'app.kubernetes.io/managed-by': 'commodore',
    'app.kubernetes.io/part-of': 'syn',
    'app.kubernetes.io/component': 'openshift4-local-storage',
  },
};

// See https://docs.openshift.com/container-platform/4.8/cicd/builds/securing-builds-by-strategy.html#builds-disabling-build-strategy-globally_securing-builds-by-strategy
// local patch = {
//   apiVersion: 'v1',
//   kind: 'ResourceQuota',
//   metadata: {
//     name: 'openshift4-local-storage-restrict-%s' % vn,
//     labels: {
//       'app.kubernetes.io/part-of': 'openshift4-local-storage',
//     },
//   },
//   spec: {
//     hard: {
//       ['%s.storageclass.storage.k8s.io/persistentvolumeclaims' % sc]: '0'
//       for sc in std.objectFields(volspec.storage_class_devices)
//     },
//   },
// };

local serviceAccount = {
  apiVersion: 'v1',
  kind: 'ServiceAccount',
  metadata: {
    name: 'openshift4-local-storage-resourcequota-restriction',
    namespace: inv.parameters.espejote.namespace,
  } + metadataPatch,
};

local clusterRole = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'ClusterRole',
  metadata: {
    name: 'syn-espejote:openshift4-local-storage-resourcequota-restriction',
  } + metadataPatch,
  rules: [
    {
      apiGroups: [ '' ],
      resources: [ 'namespaces' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
    {
      apiGroups: [ '' ],
      resources: [ 'resourcequotas' ],
      verbs: [ '*' ],
    },
    {
      apiGroups: [ 'espejote.io' ],
      resources: [ 'jsonnetlibraries' ],
      resourceNames: [ 'openshift4-local-storage-resourcequota-restriction' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};
local clusterRoleBinding = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'ClusterRoleBinding',
  metadata: {
    name: 'syn-espejote:openshift4-local-storage-resourcequota-restriction',
  } + metadataPatch,
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'ClusterRole',
    name: clusterRole.metadata.name,
  },
  subjects: [
    {
      kind: 'ServiceAccount',
      name: serviceAccount.metadata.name,
      namespace: serviceAccount.metadata.namespace,
    },
  ],
};

local role = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'Role',
  metadata: {
    name: 'syn-espejote:openshift4-local-storage-resourcequota-restriction',
    namespace: inv.parameters.espejote.namespace,
  } + metadataPatch,
  rules: [
    {
      apiGroups: [ 'espejote.io' ],
      resources: [ 'jsonnetlibraries' ],
      resourceNames: [ 'openshift4-local-storage-resourcequota-restriction' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};
local roleBinding = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'RoleBinding',
  metadata: {
    name: 'syn-espejote:openshift4-local-storage-resourcequota-restriction',
  } + metadataPatch,
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'Role',
    name: role.metadata.name,
  },
  subjects: [
    {
      kind: 'ServiceAccount',
      name: serviceAccount.metadata.name,
      namespace: serviceAccount.metadata.namespace,
    },
  ],
};

local jsonnetLibrary = esp.jsonnetLibrary('openshift4-local-storage-resourcequota-restriction', inv.parameters.espejote.namespace) {
  spec: {
    data: {
      'config.json': std.manifestJson({
        local_volumes: params.local_volumes,
      }),
    },
  },
};

local managedResource = esp.managedResource('openshift4-local-storage-resourcequota-restriction', inv.parameters.espejote.namespace) {
  metadata+: {
    annotations+: {
      'syn.tools/description': |||
        Manages ResourceQuotas for local volumes.

        This component will restrict the creation of PersistentVolumeClaims for local volumes,
        by creating ResourceQuotas for each local volume.
        Only namespaces that are part of a rook-ceph cluster will be exempted from this restriction.
      |||,
    },
  } + metadataPatch,
  spec: {
    applyOptions: {
      force: true,
    },
    serviceAccountRef: {
      name: serviceAccount.metadata.name,
    },
    template: importstr 'espejote-templates/resourcequota-restrictions.jsonnet',
    context: [
      {
        name: 'namespaces',
        resource: {
          apiVersion: 'v1',
          kind: 'Namespace',
        },
      },
      {
        name: 'resourcequotas',
        resource: {
          apiVersion: 'v1',
          kind: 'ResourceQuota',
          namespace: '',
          labelSelector: {
            matchLabels: {
              'app.kubernetes.io/managed-by': 'espejote',
              'app.kubernetes.io/part-of': 'syn',
              'app.kubernetes.io/component': 'openshift4-local-storage',
            },
          },
        },
      },
    ],
    triggers: [
      {
        name: 'jslib',
        watchResource: {
          apiVersion: jsonnetLibrary.apiVersion,
          kind: 'JsonnetLibrary',
          name: jsonnetLibrary.metadata.name,
          namespace: jsonnetLibrary.metadata.namespace,
        },
      },
      {
        name: 'namespace',
        watchContextResource: {
          name: 'namespaces',
        },
      },
      {
        name: 'resourcequota',
        watchContextResource: {
          name: 'resourcequotas',
        },
      },
    ],
  },
};

{
  localvolumes: volumes,
  dynamic_restrictions: [
    serviceAccount,
    clusterRole,
    clusterRoleBinding,
    role,
    roleBinding,
    jsonnetLibrary,
    managedResource,
  ],
}
