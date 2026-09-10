// The former test performed a real login through OpenD's removed XML-password
// flow and deleted its Compose project volume. Keep this explicit skip until
// the isolated E2E phase supplies a safe replacement.

import { it } from 'node:test'

it('legacy real-login E2E is disabled for the OpenD 10.10.7008 wrapper', {
  skip: 'requires a redesigned isolated, operator-only acceptance flow'
}, () => {})
