-- Run this in your Supabase SQL Editor

-- 1. Create Tables
CREATE TABLE IF NOT EXISTS roommates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  avatar_url TEXT,
  order_index INT NOT NULL UNIQUE -- 0 to 4
);

CREATE TABLE IF NOT EXISTS chore_rotations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  week_start_date DATE NOT NULL UNIQUE, -- Always a Monday
  roommate_id UUID REFERENCES roommates(id),
  is_completed BOOLEAN DEFAULT FALSE,
  swapped_from_id UUID REFERENCES roommates(id), -- Tracks original if swapped
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Enable Row Level Security (RLS)
ALTER TABLE roommates ENABLE ROW LEVEL SECURITY;
ALTER TABLE chore_rotations ENABLE ROW LEVEL SECURITY;

-- 3. Create basic policies (Allow all for demo purposes)
-- NOTE: In production, you'd want more restrictive policies
CREATE POLICY "Public Read Access" ON roommates FOR SELECT USING (true);
CREATE POLICY "Public Read Access" ON chore_rotations FOR SELECT USING (true);
CREATE POLICY "Public Write Access" ON chore_rotations FOR ALL USING (true);

-- 4. Seed Data
INSERT INTO roommates (name, order_index) VALUES
('Alex', 0),
('Jordan', 1),
('Taylor', 2),
('Morgan', 3),
('Casey', 4)
ON CONFLICT (order_index) DO NOTHING;
