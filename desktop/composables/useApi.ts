import { useAuthStore } from '~/stores/auth'

export const useApi = () => {
    const config = useRuntimeConfig()
    const baseURL = config.public.apiBase as string

    const fetchWithAuth = async (path: string, opts: RequestInit = {}) => {
        const auth = useAuthStore()
        const headers: HeadersInit = {
            'Content-Type': 'application/json',
            ...(auth.token ? { Authorization: `Bearer ${auth.token}` } : {}),
            ...((opts.headers ?? {}) as Record<string, string>),
        }
        const res = await fetch(`${baseURL}${path}`, { ...opts, headers })
        if (res.status === 401) {
            auth.logout()
            navigateTo('/login')
            throw new Error('Unauthorized')
        }
        if (!res.ok) {
            const data = await res.json().catch(() => ({}))
            throw new Error(data?.detail ?? `HTTP ${res.status}`)
        }
        return res.json()
    }

    // ── Auth ──────────────────────────────────────────────────────────────────
    const loginWithGoogle = async (idToken: string) => {
        const data = await fetchWithAuth('/auth/google/token', {
            method: 'POST',
            body: JSON.stringify({ id_token: idToken }),
        })
        return data as { access_token: string }
    }

    // ── Decks ─────────────────────────────────────────────────────────────────
    const getDecks = () => fetchWithAuth('/decks') as Promise<Deck[]>
    const createDeck = (name: string) =>
        fetchWithAuth('/decks', { method: 'POST', body: JSON.stringify({ name }) })
    const deleteDeck = (id: string) =>
        fetchWithAuth(`/decks/${id}`, { method: 'DELETE' })
    const getDueCards = (deckId: string) =>
        fetchWithAuth(`/decks/${deckId}/due`) as Promise<Card[]>
    const getCards = (deckId: string) =>
        fetchWithAuth(`/cards?deck_id=${deckId}`) as Promise<Card[]>
    const updateCardRating = (cardId: string, rating: number) =>
        fetchWithAuth(`/cards/${cardId}/review`, {
            method: 'POST',
            body: JSON.stringify({ rating }),
        })
    const createCard = (deckId: string, word: string, translation: string) =>
        fetchWithAuth('/cards', {
            method: 'POST',
            body: JSON.stringify({ deck_id: deckId, word, translation }),
        })
    const deleteCard = (cardId: string) =>
        fetchWithAuth(`/cards/${cardId}`, { method: 'DELETE' })

    // ── AI ────────────────────────────────────────────────────────────────────
    const translate = (text: string, sourceLang: string, targetLang: string) =>
        fetchWithAuth('/ai/translate', {
            method: 'POST',
            body: JSON.stringify({ text, source_lang: sourceLang, target_lang: targetLang }),
        }) as Promise<{ translation: string }>

    const generateWords = (deckId: string, topic: string, level: string, count: number) =>
        fetchWithAuth('/ai/generate-words', {
            method: 'POST',
            body: JSON.stringify({ deck_id: deckId, topic, level, count }),
        })

    const enrichWord = (word: string, sourceLang = 'en') =>
        fetchWithAuth('/ai/enrich-word', {
            method: 'POST',
            body: JSON.stringify({ word, source_lang: sourceLang }),
        })

    const evaluateWriting = (text: string, taskType: string, timeSecs?: number) =>
        fetchWithAuth('/ai/evaluate-writing', {
            method: 'POST',
            body: JSON.stringify({
                text,
                task_type: taskType,
                time_used_seconds: timeSecs,
                word_limit_min: taskType === 'task1' ? 150 : 250,
                word_limit_max: taskType === 'task1' ? 200 : 300,
            }),
        }) as Promise<WritingResult>

    const getWritingHistory = () =>
        fetchWithAuth('/ai/writing-history') as Promise<WritingHistoryItem[]>
    const getWritingSubmission = (id: string) =>
        fetchWithAuth(`/ai/writing-history/${id}`) as Promise<WritingSubmission>

    // ── YouTube / IELTS ───────────────────────────────────────────────────────
    const processVideo = (url: string) =>
        fetchWithAuth('/youtube/process', {
            method: 'POST',
            body: JSON.stringify({ url }),
        }) as Promise<VideoResult>

    const getYoutubeHistory = () =>
        fetchWithAuth('/youtube/history') as Promise<VideoHistoryItem[]>

    const askVideoQuestion = (videoId: string, question: string) =>
        fetchWithAuth(`/youtube/${videoId}/ask`, {
            method: 'POST',
            body: JSON.stringify({ question }),
        }) as Promise<{ answer: string }>

    const generateExamPart = (partNum: number) =>
        fetchWithAuth(`/youtube/exam/generate-part?part_num=${partNum}`, { method: 'POST' }) as Promise<ExamPart>

    return {
        loginWithGoogle,
        getDecks, createDeck, deleteDeck,
        getDueCards, getCards, updateCardRating, createCard, deleteCard,
        translate, generateWords, enrichWord,
        evaluateWriting, getWritingHistory, getWritingSubmission,
        processVideo, getYoutubeHistory, askVideoQuestion, generateExamPart,
    }
}

// ── Types ──────────────────────────────────────────────────────────────────
export interface Deck { id: string; name: string; card_count?: number }
export interface Card {
    id: string; deck_id: string; word: string; translation: string
    example?: string; transcription?: string; pronunciation_url?: string
    senses?: Sense[]; part_of_speech?: string
}
export interface Sense { part_of_speech: string; translation: string; example?: string }
export interface WritingResult {
    submission_id: string; band_score?: number; evaluation: string
    corrected_text: string; errors: WritingError[]; recommendations: string
}
export interface WritingError { type: string; original: string; correction: string; explanation: string }
export interface WritingHistoryItem { id: string; word_count: number; created_at: string; evaluation_preview: string }
export interface WritingSubmission extends WritingResult {
    id: string; original_text: string; word_count: number
    task_type: string; created_at: string
}
export interface VideoResult {
    id: string; video_id: string; url: string; title?: string
    transcription: string; translation: string; summary?: string
    questions?: VideoQuestion[]
}
export interface VideoQuestion {
    type: string; question: string; options: string[]
    answer: string; explanation: string
}
export interface VideoHistoryItem extends VideoResult { viewed_at: string }
export interface ExamPart {
    part_number: number; video_id: string; url: string
    transcription: string; questions: ExamQuestion[]
}
export interface ExamQuestion {
    type: string; question: string; options: string[]
    answer: string; explanation: string
}
