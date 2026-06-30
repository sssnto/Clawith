# Fork Maintenance

This fork contains repository-specific GitHub Actions configuration that is not present upstream.

## Safe upstream synchronization

1. Open **Sync fork** on GitHub.
2. Choose **Update branch**.
3. Do not choose **Discard commits**. It replaces fork history and removes fork-specific files.
4. Do not force push `main`.
5. Confirm `.github/workflows/docker-publish.yml` still exists after synchronization.

Create release tags only from commits containing the Docker publishing workflow.
