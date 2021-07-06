local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_local_storage;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('openshift4-local-storage', params.namespace);

{
  'openshift4-local-storage': app,
}
