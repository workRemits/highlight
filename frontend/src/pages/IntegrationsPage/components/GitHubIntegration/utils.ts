import { GetBaseURL } from '@util/window'
import { btoaSafe } from '@/util/string'
import {
	useGetGitHubIntegrationSettingsQuery,
	useUpdateIntegrationProjectSettingsMutation,
} from '@graph/hooks'
import {
	GetGitHubIntegrationSettingsQuery,
	namedOperations,
	UpdateIntegrationProjectSettingsMutationVariables,
} from '@graph/operations'
import { IntegrationType } from '@graph/schemas'
import { useIntegration } from '@pages/IntegrationsPage/components/common/useIntegration'
import useLocalStorage from '@rehooks/local-storage'

export const GitHubRepoSelectionKey = 'highlight-github-default-repo'

export const useGitHubIntegration = () => {
	const [, , removeGitHubRepoId] = useLocalStorage(GitHubRepoSelectionKey, '')
	const hook = useIntegration<
		GetGitHubIntegrationSettingsQuery,
		Omit<UpdateIntegrationProjectSettingsMutationVariables, 'workspace_id'>
	>(
		IntegrationType.GitHub,
		namedOperations.Query.GetGitHubIntegrationSettings,
		useGetGitHubIntegrationSettingsQuery,
		useUpdateIntegrationProjectSettingsMutation,
	)
	return {
		...hook,
		removeIntegration: () => {
			// clear selected repo on integration uninstall
			removeGitHubRepoId()
			return hook.removeIntegration()
		},
	}
}

export const getGitHubInstallationOAuthUrl = (
	projectId: string,
	workspaceId: string,
) => {
	const state = {
		next: window.location.pathname,
		project_id: projectId,
		workspace_id: workspaceId,
	}

	// redirect_uri is required when the GitHub App has multiple callback URLs
	// registered (we have prod + staging). Without it GitHub picks the first
	// registered URL, which can send staging users to prod (or vice versa).
	const redirectUri = `${GetBaseURL()}/callback/github`

	return (
		`https://github.com/apps/wremit-highlight/installations/new` +
		`?state=${btoaSafe(JSON.stringify(state))}` +
		`&redirect_uri=${encodeURIComponent(redirectUri)}`
	)
}
