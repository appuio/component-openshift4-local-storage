local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_local_storage;

local namespace =
  kube.Namespace(params.namespace)
  {
    metadata+: {
      annotations+: {
        // Allow pods to be scheduled on any node
        // Required to be able to configure local storage PVs on
        // infrastructure nodes.
        'openshift.io/node-selector': '',
      },
      labels+: {
        'openshift.io/cluster-monitoring': 'true',
      },
    },
  };

local operator_group =
  kube._Object(
    'operators.coreos.com/v1',
    'OperatorGroup',
    'openshift-local-storage'
  ) {
    metadata+: {
      namespace: params.namespace,
    },
    spec: {
      targetNamespaces: [
        params.namespace,
      ],
    },
  };

local subscription =
  kube._Object(
    'operators.coreos.com/v1alpha1',
    'Subscription',
    'local-storage-operator',
  ) {
    metadata+: {
      namespace: params.namespace,
    },
    spec: {
      channel: params.local_storage_operator.channel,
      installPlanApproval: 'Automatic',
      name: 'local-storage-operator',
      source: 'redhat-operators',
      sourceNamespace: 'openshift-marketplace',
    },
  };

local lvs = import 'localvolumes.libsonnet';

{
  '00_namespace': namespace,
  '10_operator_group': operator_group,
  '20_olm_subscription': subscription,
  '30_localvolumes': lvs.localvolumes,
  '40_storageclass_syncconfigs': lvs.restriction_syncconfigs,
}
