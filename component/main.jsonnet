local kap = import 'lib/kapitan.libjsonnet';
local operatorlib = import 'lib/openshift4-operators.libsonnet';

local inv = kap.inventory();
local params = inv.parameters.openshift4_local_storage;

local namespace = {
  apiVersion: 'v1',
  kind: 'Namespace',
  metadata: {
    annotations: {
      // Allow pods to be scheduled on any node
      // Required to be able to configure local storage PVs on
      // infrastructure nodes.
      'openshift.io/node-selector': '',
    },
    labels: {
      name: 'openshift-local-storage',
      'openshift.io/cluster-monitoring': 'true',
    },
    name: params.namespace,
  },
};

local operatorGroup = operatorlib.OperatorGroup('openshift-local-storage') {
  metadata+: {
    namespace: params.namespace,
  },
  spec: {
    targetNamespaces: [
      params.namespace,
    ],
  },
};

local subscription = std.prune(operatorlib.namespacedSubscription(
  params.namespace,
  'local-storage-operator',
  params.local_storage_operator.channel,
  'redhat-operators',
  'openshift-marketplace'
));

local lvs = import 'localvolumes.libsonnet';

{
  '00_namespace': namespace,
  '10_operator_group': operatorGroup,
  '20_olm_subscription': subscription,
  '30_localvolumes': lvs.localvolumes,
  '40_dynamic_restrictions': lvs.dynamic_restrictions,
}
