export default defineNuxtRouteMiddleware((to) => {
    const auth = useAuthStore()
    auth.loadFromStorage()
    if (!auth.isLoggedIn && to.path !== '/login') {
        return navigateTo('/login')
    }
})
