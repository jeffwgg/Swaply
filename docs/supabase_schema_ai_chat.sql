-- Create ai_messages table
CREATE TABLE public.ai_messages (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    is_ai BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable Row Level Security (RLS)
ALTER TABLE public.ai_messages ENABLE ROW LEVEL SECURITY;

-- Enable Realtime so the Flutter app can stream AI messages instantly
ALTER PUBLICATION supabase_realtime ADD TABLE public.ai_messages;

-- Create policies
CREATE POLICY "Users can view their own AI messages" 
ON public.ai_messages FOR SELECT 
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own AI messages" 
ON public.ai_messages FOR INSERT 
WITH CHECK (auth.uid() = user_id);
