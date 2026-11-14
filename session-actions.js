(function (root) {
  'use strict';
  function createSessionActions(auth) {
    let pending = null;
    async function perform(scope) {
      if (!['global', 'local'].includes(scope)) throw new Error('Unsupported sign-out scope');
      let error = null;
      try { error = (await auth.signOut({scope}))?.error || null; }
      catch (failure) { error = failure; }
      if (!error) return {localCleared: true, serverConfirmed: true, scope};
      if (scope === 'global') return {localCleared: false, serverConfirmed: false, scope, error};
      // The pinned SDK clears local credentials on local-scope network errors.
      // Verify this instead of treating a failed request as successful logout.
      try {
        const session = await auth.getSession();
        if (!session.error && !session.data?.session) {
          return {localCleared: true, serverConfirmed: false, scope, error};
        }
      } catch (_) { /* Fail closed: caller must retain the warning screen. */ }
      return {localCleared: false, serverConfirmed: false, scope, error};
    }
    return {
      signOut(scope = 'global') {
        if (pending) return pending;
        pending = perform(scope).finally(() => { pending = null; });
        return pending;
      }
    };
  }
  if (typeof module === 'object' && module.exports) module.exports = {createSessionActions};
  else root.createSessionActions = createSessionActions;
})(globalThis);
