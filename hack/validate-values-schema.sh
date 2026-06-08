#!/bin/bash
# Copyright 2026 The clusterprofile-integration-for-argocd Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true

SCRIPT_DIR="$(cd -- "$(dirname "$0")" >/dev/null 2>&1; pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHART_ROOT="${REPO_ROOT}/install/helm-repo"

required_binaries="yq jq helm"
for bin in $required_binaries; do
	if ! command -v "$bin" >/dev/null 2>&1; then
		echo "Error: Required binary '$bin' not found in \$PATH" >&2
		exit 1
	fi
done

if ! yq --version 2>&1 | grep -qi 'mikefarah'; then
	echo "Error: incompatible yq detected. This script requires Mike Farah's yq." >&2
	echo "  Detected: $(yq --version 2>&1 | head -n1)" >&2
	exit 1
fi

extract_yaml_paths() {
	local values_file="$1"
	yq eval -o=json "$values_file" | jq -r '
		paths
		| map(select(type == "string"))
		| select(length > 0)
		| join(".")
	'
}

extract_schema_paths() {
	local schema_file="$1"
	jq -r '
		def extract_properties($prefix):
			if type == "object" then
				(if .properties then .properties else . end)
				| to_entries[]
				| ($prefix + (if $prefix == "" then "" else "." end) + .key) as $path
				| $path,
				  (.value | extract_properties($path))
			else
				empty
			end;

		.properties | extract_properties("")
	' "$schema_file"
}

has_additional_properties() {
	local schema_file="$1"
	local path="$2"
	local path_parts
	path_parts=$(echo "$path" | tr '.' '\n')

	local current_path=""
	for part in $path_parts; do
		if [ -n "$current_path" ]; then
			current_path="${current_path}.${part}"
		else
			current_path="$part"
		fi

		local level_schema
		level_schema=$(jq -r --arg path "$current_path" '
			def get_schema($path_parts):
				. as $root |
				reduce $path_parts[] as $part (
					$root.properties // {};
					if type == "object" then
						(if .properties then .properties[$part] else .[$part] end) // {}
					else
						{}
					end
				);

			($path | split(".")) as $parts |
			get_schema($parts)
		' "$schema_file")

		local additional_props
		additional_props=$(echo "$level_schema" | jq -r '.additionalProperties // false')

		if [ "$additional_props" = "true" ]; then
			return 0
		fi
		if echo "$additional_props" | jq -e 'type == "object"' >/dev/null 2>&1; then
			return 0
		fi
	done

	return 1
}

validate_chart() {
	local chart_dir="$1"
	local values_yaml="${chart_dir}/values.yaml"
	local schema_json="${chart_dir}/values.schema.json"

	echo "==> Validating ${chart_dir#"$REPO_ROOT/"}"

	if [ ! -f "$values_yaml" ]; then
		echo "Error: values.yaml not found at $values_yaml" >&2
		return 1
	fi
	if [ ! -f "$schema_json" ]; then
		echo "Error: values.schema.json not found at $schema_json" >&2
		return 1
	fi

	echo "==> Running helm lint"
	if ! lint_output=$(helm lint --quiet "$chart_dir" 2>&1); then
		echo "Error: helm lint failed:" >&2
		echo "$lint_output" >&2
		return 1
	fi

	local yaml_paths_array
	local schema_paths_array
	yaml_paths_array=$(extract_yaml_paths "$values_yaml" | sort -u)
	schema_paths_array=$(extract_schema_paths "$schema_json" | sort -u)

	local missing_paths=""
	local missing_count=0
	while IFS= read -r path; do
		[ -z "$path" ] && continue
		if echo "$schema_paths_array" | grep -Fxq "$path"; then
			continue
		fi
		if has_additional_properties "$schema_json" "$path"; then
			continue
		fi
		if [ -z "$missing_paths" ]; then
			missing_paths="$path"
		else
			missing_paths="$missing_paths"$'\n'"$path"
		fi
		missing_count=$((missing_count + 1))
	done <<< "$yaml_paths_array"

	if [ "$missing_count" -gt 0 ]; then
		echo "Error: The following fields from values.yaml are missing in values.schema.json:" >&2
		echo "$missing_paths" | while IFS= read -r path; do
			[ -n "$path" ] && echo "  - $path" >&2
		done
		return 1
	fi

	echo "✓ values.yaml is represented in values.schema.json"
}

charts=()
if [ "$#" -gt 0 ]; then
	for chart in "$@"; do
		charts+=("$chart")
	done
else
	while IFS= read -r chart; do
		charts+=("$chart")
	done < <(find "$CHART_ROOT" -mindepth 1 -maxdepth 1 -type d -exec test -f '{}/Chart.yaml' ';' -print | sort)
fi

if [ "${#charts[@]}" -eq 0 ]; then
	echo "Error: no charts found under $CHART_ROOT" >&2
	exit 1
fi

for chart in "${charts[@]}"; do
	validate_chart "$chart"
done
