local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_local_storage;

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

local localvolumes = [
  params.local_volumes[vn]
  for vn in std.objectFields(params.local_volumes)
];

{
  '00_namespace': kube.Namespace(params.namespace),
  '10_operator_group': operator_group,
  '20_olm_subscription': subscription,
  '30_localvolumes': localvolumes,
}
