local esp = import 'espejote.libsonnet';
local config = import 'lib/openshift4-local-storage-resourcequota-restriction/config.json';

local context = esp.context();

local generateResourceQuota(vn, namespace) = {
  apiVersion: 'v1',
  kind: 'ResourceQuota',
  metadata: {
    annotations: {
      'syn.tools/source': 'https://github.com/appuio/component-openshift4-local-storage.git',
    },
    labels: {
      'app.kubernetes.io/managed-by': 'espejote',
      'app.kubernetes.io/part-of': 'syn',
      'app.kubernetes.io/component': 'openshift4-local-storage',
    },
    name: 'openshift4-local-storage-restrict-%s' % vn,
    namespace: namespace.metadata.name,
  },
  spec: {
    hard: {
      ['%s.storageclass.storage.k8s.io/persistentvolumeclaims' % sc]: '0'
      for sc in std.objectFields(std.get(config.local_volumes, vn, {}).storage_class_devices)
    },
  },
};

// Reconcile the given namespace.
local reconcileNamespace(namespace) =
  local restrictedTo(vn, namespace) =
    local nsLabels = std.get(namespace.metadata, 'labels', {});
    local evaluate(key, condition) =
      if std.objectHas(condition, 'values') then
        local labelval = std.get(nsLabels, key);
        labelval != null && std.member(condition.values, labelval)
      else
        std.objectHas(nsLabels, key);
    std.objectValues(std.mapWithKey(evaluate, std.get(config.local_volumes, vn).restricted_to));
  [
    // We only want to generate quotas for local_volumes entries that configure `restricted_to`
    if std.objectHas(std.get(config.local_volumes, vn), 'restricted_to') then (
      if std.any(restrictedTo(vn, namespace)) then
        esp.markForDelete(generateResourceQuota(vn, namespace))
      else
        generateResourceQuota(vn, namespace)
    )
    for vn in std.objectFields(config.local_volumes)
  ];

// check if the object is getting deleted by checking if it has
// `metadata.deletionTimestamp`.
local inDelete(obj) = std.get(obj.metadata, 'deletionTimestamp', '') != '';

// Do the thing
if esp.triggerName() == 'namespace' then (
  // Handle single namespace update on namespace trigger
  local nsTrigger = esp.triggerData();
  // nsTrigger.resource can be null if we're called when the namespace is getting
  // deleted. If it's not null, we still don't want to do anything when the
  // namespace is getting deleted.
  if nsTrigger.resource != null && !inDelete(nsTrigger.resource) then
    reconcileNamespace(nsTrigger.resource)
) else if esp.triggerName() == 'resourcequota' then (
  // Handle single namespace update on resourcequota trigger
  local namespace = esp.triggerData().resourceEvent.namespace;
  std.flattenArrays([
    reconcileNamespace(ns)
    for ns in context.namespaces
    if ns.metadata.name == namespace && !inDelete(ns)
  ])
) else (
  // Reconcile all namespaces for jsonnetlibrary update or managedresource
  // reconcile.
  local namespaces = context.namespaces;
  std.flattenArrays([
    reconcileNamespace(ns)
    for ns in namespaces
    if !inDelete(ns)
  ])
)
