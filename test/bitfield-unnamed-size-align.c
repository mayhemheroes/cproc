struct s {
	int : 8;
	char c;
};
union u {
	int : 8;
	char c;
};
int s1 = sizeof(struct s);
int s2 = alignof(struct s);
int u1 = sizeof(union u);
int u2 = alignof(union u);
