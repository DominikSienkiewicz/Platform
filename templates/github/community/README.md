# .github

Default community health files for the public repositories of
[DominikSienkiewicz](https://github.com/DominikSienkiewicz). GitHub uses a file from this repository in every public
repository of the account that has no file of its own with that name.

| File | What a repository without its own file gets |
|---|---|
| `CODE_OF_CONDUCT.md` | the Contributor Covenant 2.1 and a private way to report a violation |
| `CONTRIBUTING.md` | how to propose and submit a change |
| `SECURITY.md` | the supported versions and how to report a vulnerability privately |
| `SUPPORT.md` | where to get help, and where not to |
| `.github/pull_request_template.md` | the pull request description and checklist |
| `.github/ISSUE_TEMPLATE/` | the bug, feature request and question forms; blank issues are off and the security policy is linked |

A repository keeps control of its own files. A file that exists in the repository wins over the default of the same
name. A repository with its own `.github/ISSUE_TEMPLATE` folder uses none of the default forms.

The forms set no labels, because GitHub requires a label that a template names to exist in this repository and in
every repository that uses the template. This repository must stay public for the defaults to apply.
