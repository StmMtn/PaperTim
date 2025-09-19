--
-- PostgreSQL database dump
--

\restrict fybRCqCCFinIan2JafzNhmxrrPEULKGxqQjbtEBw3aRXjY1LBEryy4MfcNjp6X1

-- Dumped from database version 15.14 (Debian 15.14-1.pgdg13+1)
-- Dumped by pg_dump version 15.14 (Debian 15.14-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: player_stats; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.player_stats (
    user_id integer NOT NULL,
    trophies integer DEFAULT 0 NOT NULL,
    games_played integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.player_stats OWNER TO postgres;

--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id integer NOT NULL,
    username text NOT NULL,
    password_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_id_seq OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Data for Name: player_stats; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.player_stats (user_id, trophies, games_played) FROM stdin;
7	-20	2
8	20	2
6	10	3
1	163	50
2	-87	44
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, username, password_hash, created_at) FROM stdin;
1	xuittt	$2b$10$K1x56YaaCo/1Cv99y7dhIuMEemrrZ/cqtar0Rr0/vU.JOPMD93dYS	2025-09-17 10:07:49.345709+00
2	Stm.	$2b$10$EuX6oYERkQpjvYMSPs990.RU/u.nJtaJISU6zxadWfYwKD0MEjfkG	2025-09-17 10:29:44.598641+00
6	Player1	$2b$10$r2oaGpPmrj569PfnzCRjFeAIrrzPG7VSx5dXOAsslJ46Yh8W5pPPO	2025-09-17 18:40:23.888209+00
7	Player2	$2b$10$Jf4O2TpB9tk5WQFnk/1Bqu9b/A1p1HPi/04EpfH.Fr.Yul5AR74rW	2025-09-17 18:40:34.86627+00
8	Player3	$2b$10$7Pf1v.ExG9Fck4Nxrv6dOuBW4/TDiUoCMY9KtutBQpqJYdD7/KH7S	2025-09-17 18:40:41.118895+00
\.


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_id_seq', 8, true);


--
-- Name: player_stats player_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.player_stats
    ADD CONSTRAINT player_stats_pkey PRIMARY KEY (user_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: player_stats player_stats_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.player_stats
    ADD CONSTRAINT player_stats_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict fybRCqCCFinIan2JafzNhmxrrPEULKGxqQjbtEBw3aRXjY1LBEryy4MfcNjp6X1

