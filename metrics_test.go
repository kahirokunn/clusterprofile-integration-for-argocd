package main

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/go-logr/logr"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"
	"github.com/stretchr/testify/require"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterinventory "sigs.k8s.io/cluster-inventory-api/apis/v1alpha1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

const (
	testConflictGroupSizeMetric = "argocd_clusterprofile_inventory_member_conflict_group_size"
	testInventoryGroupsMetric   = "argocd_clusterprofile_inventory_member_groups"
	testInvalidProfilesMetric   = "argocd_clusterprofile_inventory_member_id_invalid_profiles"
	testCollectionErrorsMetric  = "argocd_clusterprofile_inventory_collection_errors_total"
)

type switchableErrorReader struct {
	client.Reader
	mu  sync.RWMutex
	err error
}

func (r *switchableErrorReader) List(
	ctx context.Context,
	list client.ObjectList,
	options ...client.ListOption,
) error {
	r.mu.RLock()
	err := r.err
	r.mu.RUnlock()
	if err != nil {
		return err
	}
	return r.Reader.List(ctx, list, options...)
}

func (r *switchableErrorReader) setError(err error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.err = err
}

func TestClusterProfileMetricsInventoryState(t *testing.T) {
	createdAt := time.Date(2026, time.September, 3, 12, 0, 0, 0, time.UTC)
	uniqueA := newInventoryClusterProfile("unique-a", teamANamespace, "shared", createdAt)
	uniqueB := newInventoryClusterProfile("unique-b", teamBNamespace, "shared", createdAt)
	duplicateOldest := newInventoryClusterProfile("duplicate-oldest", testNamespace, "duplicate", createdAt)
	duplicateNewer := newInventoryClusterProfile(
		"duplicate-newer",
		testNamespace,
		"duplicate",
		createdAt.Add(time.Minute),
	)
	ambiguousFirst := newInventoryClusterProfile("ambiguous-first", testNamespace, "ambiguous", createdAt)
	ambiguousSecond := newInventoryClusterProfile("ambiguous-second", testNamespace, "ambiguous", createdAt)
	ambiguousLater := newInventoryClusterProfile(
		"ambiguous-later",
		testNamespace,
		"ambiguous",
		createdAt.Add(time.Minute),
	)
	invalid := newInventoryClusterProfile("invalid", testNamespace, "", createdAt)
	absent := newInventoryClusterProfile("absent", testNamespace, "", createdAt)
	delete(absent.Labels, inventoryMemberIDLabel)
	terminating := newInventoryClusterProfile("terminating", testNamespace, "terminating", createdAt)
	deletionTimestamp := metav1.NewTime(createdAt.Add(2 * time.Minute))
	terminating.DeletionTimestamp = &deletionTimestamp
	terminating.Finalizers = []string{"test.example.com/retain"}

	objects := []client.Object{
		uniqueA,
		uniqueB,
		duplicateOldest,
		duplicateNewer,
		ambiguousFirst,
		ambiguousSecond,
		ambiguousLater,
		invalid,
		absent,
		terminating,
	}
	reader := fake.NewClientBuilder().WithScheme(newTestScheme(t)).WithObjects(objects...).Build()
	metrics := newClusterProfileMetrics(reader, logr.Discard(), false)
	registry := prometheus.NewPedanticRegistry()
	require.NoError(t, registry.Register(metrics))

	expected := fmt.Sprintf(`
# HELP %[1]s Number of active ClusterProfiles in a duplicate or ambiguous inventory member ID group.
# TYPE %[1]s gauge
%[1]s{inventory_member_id="ambiguous",namespace="default",resolution="ambiguous"} 3
%[1]s{inventory_member_id="duplicate",namespace="default",resolution="duplicate"} 2
# HELP %[2]s Number of active inventory member groups by namespace and selection resolution.
# TYPE %[2]s gauge
%[2]s{namespace="default",resolution="ambiguous"} 1
%[2]s{namespace="default",resolution="duplicate"} 1
%[2]s{namespace="team-a",resolution="unique"} 1
%[2]s{namespace="team-b",resolution="unique"} 1
# HELP %[3]s Number of active ClusterProfiles whose inventory member ID label is present but empty.
# TYPE %[3]s gauge
%[3]s{namespace="default"} 1
`, testConflictGroupSizeMetric, testInventoryGroupsMetric, testInvalidProfilesMetric)
	require.NoError(t, testutil.GatherAndCompare(
		registry,
		strings.NewReader(expected),
		testConflictGroupSizeMetric,
		testInventoryGroupsMetric,
		testInvalidProfilesMetric,
	))
}

func TestClusterProfileMetricsRetainsLastSnapshotAfterCollectionFailure(t *testing.T) {
	createdAt := time.Date(2026, time.September, 3, 12, 0, 0, 0, time.UTC)
	profile := newInventoryClusterProfile("profile", testNamespace, "member", createdAt)
	reader := &switchableErrorReader{Reader: fake.NewClientBuilder().
		WithScheme(newTestScheme(t)).
		WithObjects(profile).
		Build()}
	metrics := newClusterProfileMetrics(reader, logr.Discard(), false)
	registry := prometheus.NewPedanticRegistry()
	require.NoError(t, registry.Register(metrics))

	require.NoError(t, testutil.GatherAndCompare(
		registry,
		strings.NewReader(fmt.Sprintf(`
# HELP %[1]s Number of active inventory member groups by namespace and selection resolution.
# TYPE %[1]s gauge
%[1]s{namespace="default",resolution="unique"} 1
`, testInventoryGroupsMetric)),
		testInventoryGroupsMetric,
	))

	reader.setError(errors.New("cache list failed"))
	require.NoError(t, testutil.GatherAndCompare(
		registry,
		strings.NewReader(fmt.Sprintf(`
# HELP %[1]s Number of failures collecting ClusterProfile inventory state from the controller cache.
# TYPE %[1]s counter
%[1]s 1
# HELP %[2]s Number of active inventory member groups by namespace and selection resolution.
# TYPE %[2]s gauge
%[2]s{namespace="default",resolution="unique"} 1
`, testCollectionErrorsMetric, testInventoryGroupsMetric)),
		testCollectionErrorsMetric,
		testInventoryGroupsMetric,
	))
}

func TestClusterProfileMetricsCountsSuccessfulSecretChanges(t *testing.T) {
	scheme := newTestScheme(t)
	profile := newBuiltinProviderClusterProfile(nil)
	controllerClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(profile).Build()
	metrics := newClusterProfileMetrics(controllerClient, logr.Discard(), false)
	reconciler := &ClusterProfileReconciler{
		Client:  controllerClient,
		Log:     logr.Discard(),
		Scheme:  scheme,
		metrics: metrics,
	}

	_, err := reconciler.Reconcile(context.Background(), profileRequest())
	require.NoError(t, err)
	_, err = reconciler.Reconcile(context.Background(), profileRequest())
	require.NoError(t, err)
	updateProfile(t, reconciler, profileKey(), func(profile *clusterinventory.ClusterProfile) {
		profile.Labels = map[string]string{environmentLabel: productionValue}
	})
	_, err = reconciler.Reconcile(context.Background(), profileRequest())
	require.NoError(t, err)
	updateProfile(t, reconciler, profileKey(), func(profile *clusterinventory.ClusterProfile) {
		profile.Status.AccessProviders = nil
	})
	_, err = reconciler.Reconcile(context.Background(), profileRequest())
	require.NoError(t, err)

	require.Equal(t, float64(1), testutil.ToFloat64(
		metrics.secretChanges.WithLabelValues(testNamespace, secretOperationCreate, "false"),
	))
	require.Equal(t, float64(1), testutil.ToFloat64(
		metrics.secretChanges.WithLabelValues(testNamespace, secretOperationUpdate, "false"),
	))
	require.Equal(t, float64(1), testutil.ToFloat64(
		metrics.secretChanges.WithLabelValues(testNamespace, secretOperationDelete, "false"),
	))
}

func TestClusterProfileMetricsDoesNotCountFailedOrMissingSecretDeletes(t *testing.T) {
	scheme := newTestScheme(t)
	baseClient := fake.NewClientBuilder().WithScheme(scheme).Build()
	metrics := newClusterProfileMetrics(baseClient, logr.Discard(), true)
	secret := newControlledSecret(newBuiltinProviderClusterProfile(nil), "secret-uid")
	reconciler := &ClusterProfileReconciler{
		Client:  baseClient,
		Log:     logr.Discard(),
		Scheme:  scheme,
		metrics: metrics,
	}

	require.NoError(t, reconciler.deleteSecretWithPreconditions(context.Background(), secret))
	reconciler.Client = &deleteConflictClient{Client: baseClient}
	require.Error(t, reconciler.deleteSecretWithPreconditions(context.Background(), secret))
	require.Equal(t, float64(0), testutil.ToFloat64(
		metrics.secretChanges.WithLabelValues(testNamespace, secretOperationDelete, "true"),
	))
}

func TestClusterProfileMetricsLabelsDryRunSecretChanges(t *testing.T) {
	metrics := newClusterProfileMetrics(nil, logr.Discard(), true)

	metrics.recordSecretChange(testNamespace, secretOperationCreate)

	require.Equal(t, float64(1), testutil.ToFloat64(
		metrics.secretChanges.WithLabelValues(testNamespace, secretOperationCreate, "true"),
	))
}
